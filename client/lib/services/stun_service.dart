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

  StunResult(this.publicIp, this.publicPort);

  @override
  String toString() => '$publicIp:$publicPort';
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

    final List<InternetAddress> addrs;
    try {
      addrs = await InternetAddress.lookup(stunHost)
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      throw Exception('DNS lookup failed for $stunHost: $e');
    }

    if (addrs.isEmpty) {
      throw Exception('DNS lookup returned empty for $stunHost');
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
      if (datagram.address.address != addr.address ||
          datagram.port != stunPort) {
        return;
      }

      try {
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

    socket.send(request, addr, stunPort);
    AppLogger.debug(_tag, 'Sent STUN request to $stunHost:$stunPort');

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
