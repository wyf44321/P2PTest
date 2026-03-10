import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:p2p_test/config/constants.dart';
import 'package:p2p_test/config/stun_servers.dart';
import 'package:p2p_test/models/self_info.dart';
import 'package:p2p_test/services/udp_service.dart';
import 'package:p2p_test/utils/logger.dart';

class StunResult {
  final String publicIp;
  final int publicPort;

  StunResult(this.publicIp, this.publicPort);

  @override
  String toString() => '$publicIp:$publicPort';
}

class NatDetectionResult {
  final NatType natType;
  final StunResult primaryResult;
  final StunResult? secondaryResult;
  final int? portDelta;

  /// All mapped ports observed from successive STUN queries.
  final List<int> portSamples;

  /// Deltas between consecutive port samples (length = portSamples.length - 1).
  final List<int> portDeltas;

  /// Whether the observed deltas are consistent enough for confident prediction.
  final bool isConsistentDelta;

  NatDetectionResult({
    required this.natType,
    required this.primaryResult,
    this.secondaryResult,
    this.portDelta,
    this.portSamples = const [],
    this.portDeltas = const [],
    this.isConsistentDelta = false,
  });
}

class StunService {
  static const String _tag = 'StunService';

  // STUN message types
  static const int _bindingRequest = 0x0001;
  static const int _bindingResponse = 0x0101;

  // STUN attribute types
  static const int _attrMappedAddress = 0x0001;
  static const int _attrXorMappedAddress = 0x0020;

  // STUN magic cookie
  static const int _magicCookie = 0x2112A442;

  static Future<StunResult> getPublicAddr(
    UdpService udpService,
    String stunHost,
    int stunPort, {
    Duration? timeout,
  }) async {
    final socket = udpService.socket;
    if (socket == null) {
      throw Exception('UDP socket not bound');
    }

    final effectiveTimeout = timeout ?? AppConstants.stunTimeout;

    final List<InternetAddress> allAddrs;
    try {
      allAddrs = await InternetAddress.lookup(stunHost)
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      throw Exception('DNS lookup failed for $stunHost: $e');
    }

    // Socket is bound to IPv4 — must filter out IPv6 addresses to avoid
    // "Operation not permitted" when sending IPv6 on an IPv4 socket.
    final addrs = allAddrs
        .where((a) => a.type == InternetAddressType.IPv4)
        .toList();

    if (addrs.isEmpty) {
      throw Exception('No IPv4 address found for $stunHost');
    }

    final addr = addrs.first;
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
        // Transaction ID verification is done inside _parseBindingResponse,
        // so we don't filter by source address — some servers respond from
        // a different IP/port (load-balancing, anycast, etc.).
        final result = _parseBindingResponse(datagram.data, txId);
        if (result != null && !completer.isCompleted) {
          timer?.cancel();
          udpService.setStunResponseHandler(null);
          completer.complete(result);
        }
      } catch (e) {
        AppLogger.debug(_tag, 'Failed to parse STUN response: $e');
      }
    });

    try {
      socket.send(request, addr, stunPort);
      AppLogger.debug(
          _tag, 'Sent STUN request to $stunHost:$stunPort (${addr.address})');
    } catch (e) {
      timer?.cancel();
      udpService.setStunResponseHandler(null);
      throw Exception('Failed to send STUN request to $stunHost: $e');
    }

    return completer.future;
  }

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

  /// Query multiple STUN servers from the same socket and compare the mapped
  /// ports.  Same port → cone NAT; different ports → symmetric NAT.
  /// Collects up to [_maxStunSamples] samples to analyse port-allocation
  /// patterns (delta consistency) for smarter prediction.
  static const int _maxStunSamples = 4;

  static Future<NatDetectionResult> detectNatType(
    UdpService udpService, {
    String? preferredServer,
  }) async {
    final servers = _buildServerList(preferredServer);

    final samples = <StunResult>[];
    final usedDestinations = <String>{};

    for (final server in servers) {
      if (samples.length >= _maxStunSamples) break;

      try {
        final addrs = await InternetAddress.lookup(server.host)
            .timeout(const Duration(seconds: 3));
        final resolved = addrs
            .where((a) => a.type == InternetAddressType.IPv4)
            .firstOrNull
            ?.address;

        final destKey = '$resolved:${server.port}';
        if (usedDestinations.contains(destKey)) continue;

        final result =
            await getPublicAddr(udpService, server.host, server.port);
        samples.add(result);
        if (resolved != null) usedDestinations.add(destKey);

        AppLogger.info(_tag,
            'NAT detect sample ${samples.length}: $result via ${server.address}');
      } catch (e) {
        AppLogger.warning(
            _tag, 'NAT detect sample failed for ${server.address}: $e');
        continue;
      }
    }

    if (samples.isEmpty) {
      throw Exception('所有 STUN 服务器获取失败');
    }

    final ports = samples.map((s) => s.publicPort).toList();

    if (samples.length < 2) {
      AppLogger.warning(
          _tag, 'Only one STUN server reachable, NAT type unknown');
      return NatDetectionResult(
        natType: NatType.unknown,
        primaryResult: samples.first,
        portSamples: ports,
      );
    }

    // All mapped ports identical → cone NAT.
    if (ports.toSet().length == 1) {
      AppLogger.info(_tag,
          'NAT type: Cone (all ${samples.length} ports identical: ${ports.first})');
      return NatDetectionResult(
        natType: NatType.cone,
        primaryResult: samples.first,
        secondaryResult: samples[1],
        portSamples: ports,
      );
    }

    // Different ports → symmetric NAT.  Compute deltas & analyse pattern.
    final deltas = <int>[];
    for (int i = 1; i < ports.length; i++) {
      deltas.add(ports[i] - ports[i - 1]);
    }

    final isConsistent = _areDeltasConsistent(deltas);

    // Use the median delta as the representative value – more robust than mean
    // when one sample is an outlier.
    final sortedAbsDeltas = deltas.map((d) => d.abs()).toList()..sort();
    final medianAbs = sortedAbsDeltas[sortedAbsDeltas.length ~/ 2];
    final sign =
        deltas.where((d) => d > 0).length >= deltas.where((d) => d < 0).length
            ? 1
            : -1;
    final representativeDelta = sign * medianAbs;

    AppLogger.info(_tag,
        'NAT type: Symmetric (ports: ${ports.join(" → ")}, '
        'deltas: ${deltas.join(", ")}, '
        'consistent: $isConsistent, representative delta: $representativeDelta)');

    return NatDetectionResult(
      natType: NatType.symmetric,
      primaryResult: samples.last,
      secondaryResult: samples.length > 1 ? samples[samples.length - 2] : null,
      portDelta: representativeDelta,
      portSamples: ports,
      portDeltas: deltas,
      isConsistentDelta: isConsistent,
    );
  }

  /// Deltas are "consistent" when they all share the same sign and their
  /// absolute values are within a small tolerance of each other.
  static bool _areDeltasConsistent(List<int> deltas) {
    if (deltas.length < 2) return deltas.isNotEmpty;

    final allPositive = deltas.every((d) => d > 0);
    final allNegative = deltas.every((d) => d < 0);
    if (!allPositive && !allNegative) return false;

    final absValues = deltas.map((d) => d.abs()).toList();
    final maxVal = absValues.reduce(max);
    final minVal = absValues.reduce(min);
    return (maxVal - minVal) <= 2;
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

  static Uint8List _generateTransactionId() {
    final random = Random.secure();
    return Uint8List.fromList(
        List.generate(12, (_) => random.nextInt(256)));
  }

  static Uint8List _buildBindingRequest(Uint8List txId) {
    final buffer = ByteData(20);
    // Message Type: Binding Request
    buffer.setUint16(0, _bindingRequest);
    // Message Length: 0 (no attributes)
    buffer.setUint16(2, 0);
    // Magic Cookie
    buffer.setUint32(4, _magicCookie);

    final bytes = Uint8List(20);
    bytes.setRange(0, 8, buffer.buffer.asUint8List());
    // Transaction ID
    bytes.setRange(8, 20, txId);
    return bytes;
  }

  static StunResult? _parseBindingResponse(
      Uint8List data, Uint8List expectedTxId) {
    if (data.length < 20) return null;

    final buffer = ByteData.sublistView(data);
    final msgType = buffer.getUint16(0);
    if (msgType != _bindingResponse) return null;

    // Verify magic cookie
    final cookie = buffer.getUint32(4);
    if (cookie != _magicCookie) return null;

    // Verify transaction ID
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

      // Attributes are padded to 4-byte boundaries
      final paddedLength = (attrLength + 3) & ~3;
      offset = attrStart + paddedLength;
    }

    return null;
  }

  static StunResult _parseXorMappedAddress(
      Uint8List data, int offset, ByteData buffer) {
    final port = buffer.getUint16(offset + 2) ^ (_magicCookie >> 16);

    final xorIp = buffer.getUint32(offset + 4);
    final ip = xorIp ^ _magicCookie;

    final ipStr = '${(ip >> 24) & 0xFF}.${(ip >> 16) & 0xFF}'
        '.${(ip >> 8) & 0xFF}.${ip & 0xFF}';

    return StunResult(ipStr, port);
  }

  static StunResult _parseMappedAddress(
      Uint8List data, int offset, ByteData buffer) {
    final port = buffer.getUint16(offset + 2);
    final ipStr = '${data[offset + 4]}.${data[offset + 5]}'
        '.${data[offset + 6]}.${data[offset + 7]}';

    return StunResult(ipStr, port);
  }
}
