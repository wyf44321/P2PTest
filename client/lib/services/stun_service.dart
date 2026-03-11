import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:p2p_test/config/constants.dart';
import 'package:p2p_test/config/stun_servers.dart';
import 'package:p2p_test/services/udp_service.dart';
import 'package:p2p_test/utils/logger.dart';

class StunResult {
  final String publicIp;
  final int publicPort;
  final String stunHost;
  final int stunPort;

  StunResult(this.publicIp, this.publicPort, this.stunHost, this.stunPort);

  @override
  String toString() => '$publicIp:$publicPort';
}

class NatAnalysis {
  final String natType;
  final int? portStep;
  final double portVelocity;
  final int probeTimestamp;
  final String metadata;
  final List<StunResult> results;

  NatAnalysis({
    required this.natType,
    this.portStep,
    this.portVelocity = 0,
    this.probeTimestamp = 0,
    required this.metadata,
    required this.results,
  });

  StunResult get lastResult => results.last;
}

class StunService {
  static const String _tag = 'StunService';

  static const int _bindingRequest = 0x0001;
  static const int _bindingResponse = 0x0101;
  static const int _attrMappedAddress = 0x0001;
  static const int _attrXorMappedAddress = 0x0020;
  static const int _magicCookie = 0x2112A442;

  static Future<StunResult> getPublicAddr(
    UdpService udpService,
    String stunHost,
    int stunPort, {
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? AppConstants.stunTimeout;

    final List<InternetAddress> allAddrs;
    try {
      allAddrs = await InternetAddress.lookup(stunHost)
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      throw Exception('DNS lookup failed for $stunHost: $e');
    }

    final addrs = allAddrs
        .where((a) => a.type == InternetAddressType.IPv4)
        .toList();

    if (addrs.isEmpty) {
      throw Exception('No IPv4 address found for $stunHost');
    }

    final addr = addrs.first;

    await udpService.ensureBound();
    final socket = udpService.socket;
    if (socket == null) {
      throw Exception('UDP socket not bound');
    }

    final txId = _generateTransactionId();
    final request = _buildBindingRequest(txId);

    final completer = Completer<StunResult>();
    Timer? timer;

    timer = Timer(effectiveTimeout, () {
      udpService.setStunResponseHandler(null);
      if (!completer.isCompleted) {
        completer.completeError(
            TimeoutException('STUN timeout for $stunHost:$stunPort'));
      }
    });

    udpService.setStunResponseHandler((datagram) {
      try {
        final parsed = _parseBindingResponse(datagram.data, txId);
        if (parsed != null && !completer.isCompleted) {
          timer?.cancel();
          udpService.setStunResponseHandler(null);
          udpService.recordSendTime();
          completer.complete(
              StunResult(parsed.ip, parsed.port, stunHost, stunPort));
        }
      } catch (e) {
        AppLogger.debug(_tag, 'Failed to parse STUN response: $e');
      }
    });

    try {
      socket.send(request, addr, stunPort);
      udpService.recordSendTime();
      AppLogger.debug(
          _tag, 'Sent STUN request to $stunHost:$stunPort (${addr.address})');
    } catch (e) {
      timer?.cancel();
      udpService.setStunResponseHandler(null);
      throw Exception('Failed to send STUN request to $stunHost: $e');
    }

    return completer.future;
  }

  /// Query all STUN servers sequentially, collect results, and analyze NAT type.
  ///
  /// For symmetric NAT, extracts three prediction features:
  /// - **d** (medianStep): clean per-allocation step after outlier removal
  /// - **v** (velocity): port consumption rate in ports/second
  /// - **t** (timestamp): probe completion epoch seconds for drift estimation
  static Future<NatAnalysis> analyzeNat(
    UdpService udpService, {
    String? preferredServer,
  }) async {
    final servers = _buildServerList(preferredServer);
    final results = <StunResult>[];

    final probeStart = DateTime.now();

    for (final server in servers) {
      try {
        AppLogger.info(
            _tag, 'NAT analysis: querying ${server.name} (${server.address})');
        final result =
            await getPublicAddr(udpService, server.host, server.port);
        results.add(result);
        AppLogger.info(
            _tag, 'NAT analysis: ${server.name} → ${result.publicIp}:${result.publicPort}');
      } catch (e) {
        AppLogger.warning(
            _tag, 'NAT analysis: ${server.address} failed: $e');
        continue;
      }
    }

    final probeEnd = DateTime.now();

    if (results.isEmpty) {
      throw Exception('所有 STUN 服务器获取失败');
    }

    final ports = results.map((r) => r.publicPort).toSet();
    final ips = results.map((r) => r.publicIp).toSet();

    if (ips.length > 1) {
      AppLogger.warning(_tag,
          'NAT analysis: detected multiple public IPs: $ips');
    }

    if (ports.length <= 1) {
      AppLogger.info(_tag, 'NAT analysis: all ports identical → cone (non-symmetric)');
      return NatAnalysis(
        natType: 'cone',
        metadata: 'cone',
        results: results,
      );
    }

    // Ports differ → symmetric NAT.
    final orderedPorts = results.map((r) => r.publicPort).toList();
    final deltas = <int>[];
    for (int i = 1; i < orderedPorts.length; i++) {
      final delta = (orderedPorts[i] - orderedPorts[i - 1]).abs();
      if (delta > 0) deltas.add(delta);
    }

    // Outlier removal: compute raw median, discard deltas > 3× median.
    // This separates true NAT allocation steps (1-15) from background
    // traffic noise (50-400+) that inflates the step estimate.
    final cleanDeltas = _removeOutliers(deltas);
    int medianStep = 1;
    if (cleanDeltas.isNotEmpty) {
      final sorted = List<int>.from(cleanDeltas)..sort();
      medianStep = sorted[sorted.length ~/ 2].clamp(1, 1000);
    }

    // Port velocity: overall consumption rate including background traffic.
    // Used by the receiver to estimate how far the port has drifted since
    // this probe, enabling time-compensated prediction.
    final firstPort = orderedPorts.first;
    final lastPort = orderedPorts.last;
    final probeDurationSec =
        probeEnd.difference(probeStart).inMilliseconds / 1000.0;
    double velocity = 0;
    if (probeDurationSec > 0.1 && lastPort > firstPort) {
      velocity = (lastPort - firstPort) / probeDurationSec;
    }

    final probeTimestamp = probeEnd.millisecondsSinceEpoch ~/ 1000;
    final velocityInt = velocity.round().clamp(0, 9999);

    AppLogger.info(_tag,
        'NAT analysis: ports vary (${orderedPorts.join(", ")}) → symmetric, '
        'clean_median_step=$medianStep, velocity=${velocityInt}p/s, '
        'raw_deltas=$deltas, clean_deltas=$cleanDeltas');

    return NatAnalysis(
      natType: 'sym',
      portStep: medianStep,
      portVelocity: velocity,
      probeTimestamp: probeTimestamp,
      metadata: 'sym,d=$medianStep,v=$velocityInt,t=$probeTimestamp',
      results: results,
    );
  }

  /// Remove outlier deltas caused by background traffic consuming NAT ports.
  /// Uses 3× median threshold: deltas exceeding 3× the raw median are noise.
  static List<int> _removeOutliers(List<int> deltas) {
    if (deltas.length < 3) return List.from(deltas);

    final sorted = List<int>.from(deltas)..sort();
    final rawMedian = sorted[sorted.length ~/ 2];
    if (rawMedian <= 0) return List.from(deltas);

    final threshold = rawMedian * 3;
    final clean = deltas.where((d) => d <= threshold).toList();
    return clean.isEmpty ? List.from(deltas) : clean;
  }

  /// Legacy single-result fetch (fallback to first successful server).
  static Future<StunResult> fetchPublicAddress(
    UdpService udpService, {
    String? preferredServer,
  }) async {
    final servers = _buildServerList(preferredServer);

    for (final server in servers) {
      try {
        AppLogger.info(
            _tag, 'Trying STUN server: ${server.name} (${server.address})');
        final result =
            await getPublicAddr(udpService, server.host, server.port);
        AppLogger.info(_tag, 'STUN success: $result');
        return result;
      } catch (e) {
        AppLogger.warning(
            _tag, 'STUN failed for ${server.address}: $e');
        continue;
      }
    }
    throw Exception('所有 STUN 服务器获取失败');
  }

  static List<StunServerOption> _buildServerList(String? preferredServer) {
    if (preferredServer == null || preferredServer.isEmpty) {
      return StunServers.defaultServers;
    }
    final parts = preferredServer.split(':');
    if (parts.length != 2) return StunServers.defaultServers;

    final port = int.tryParse(parts[1]);
    if (port == null) return StunServers.defaultServers;

    final preferred = StunServerOption('用户配置', parts[0], port);
    return [
      preferred,
      ...StunServers.defaultServers
          .where((s) => s.address != preferredServer),
    ];
  }

  /// Build a STUN Binding Request (20 bytes). Exposed for keepalive use.
  static Uint8List buildKeepaliveRequest() {
    final txId = _generateTransactionId();
    return _buildBindingRequest(txId);
  }

  static Uint8List _generateTransactionId() {
    final random = Random.secure();
    return Uint8List.fromList(
        List.generate(12, (_) => random.nextInt(256)));
  }

  static Uint8List _buildBindingRequest(Uint8List txId) {
    final buffer = ByteData(20);
    buffer.setUint16(0, _bindingRequest);
    buffer.setUint16(2, 0);
    buffer.setUint32(4, _magicCookie);

    final bytes = Uint8List(20);
    bytes.setRange(0, 8, buffer.buffer.asUint8List());
    bytes.setRange(8, 20, txId);
    return bytes;
  }

  static ({String ip, int port})? _parseBindingResponse(
      Uint8List data, Uint8List expectedTxId) {
    if (data.length < 20) return null;

    final buffer = ByteData.sublistView(data);
    final msgType = buffer.getUint16(0);
    if (msgType != _bindingResponse) return null;

    final cookie = buffer.getUint32(4);
    if (cookie != _magicCookie) return null;

    for (int i = 0; i < 12; i++) {
      if (data[8 + i] != expectedTxId[i]) return null;
    }

    final msgLength = buffer.getUint16(2);
    int offset = 20;
    final end = 20 + msgLength;

    while (offset + 4 <= end && offset + 4 <= data.length) {
      final attrType = buffer.getUint16(offset);
      final attrLength = buffer.getUint16(offset + 2);
      final attrStart = offset + 4;

      if (attrType == _attrXorMappedAddress &&
          attrLength >= 8 &&
          attrStart + attrLength <= data.length) {
        return _parseXorMappedAddress(data, attrStart, buffer);
      }

      if (attrType == _attrMappedAddress &&
          attrLength >= 8 &&
          attrStart + attrLength <= data.length) {
        return _parseMappedAddress(data, attrStart, buffer);
      }

      final paddedLength = (attrLength + 3) & ~3;
      offset = attrStart + paddedLength;
    }

    return null;
  }

  static ({String ip, int port}) _parseXorMappedAddress(
      Uint8List data, int offset, ByteData buffer) {
    final port = buffer.getUint16(offset + 2) ^ (_magicCookie >> 16);

    final xorIp = buffer.getUint32(offset + 4);
    final ip = xorIp ^ _magicCookie;

    final ipStr = '${(ip >> 24) & 0xFF}.${(ip >> 16) & 0xFF}'
        '.${(ip >> 8) & 0xFF}.${ip & 0xFF}';

    return (ip: ipStr, port: port);
  }

  static ({String ip, int port}) _parseMappedAddress(
      Uint8List data, int offset, ByteData buffer) {
    final port = buffer.getUint16(offset + 2);
    final ipStr = '${data[offset + 4]}.${data[offset + 5]}'
        '.${data[offset + 6]}.${data[offset + 7]}';

    return (ip: ipStr, port: port);
  }
}
