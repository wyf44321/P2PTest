import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:p2p_test/config/constants.dart';
import 'package:p2p_test/services/stun_service.dart';
import 'package:p2p_test/utils/logger.dart';

class UdpService {
  static const String _tag = 'UdpService';

  static const int pingMarker = 0xFE;
  static const int pongMarker = 0xFF;
  static const int pingPacketSize = 13;

  RawDatagramSocket? _socket;
  void Function(Datagram datagram)? _stunResponseHandler;

  /// Called when a non-STUN packet arrives from a peer.
  void Function(String ip, int port, Uint8List data)? onPeerPacketReceived;

  DateTime _lastSendTime = DateTime.now();
  Timer? _keepaliveTimer;
  InternetAddress? _keepaliveStunAddr;
  int? _keepaliveStunPort;

  final Random _random = Random();

  RawDatagramSocket? get socket => _socket;
  bool get isBound => _socket != null;

  Future<int> bind({int port = 0}) async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    _socket!.listen(_onData);
    AppLogger.info(_tag, 'UDP socket bound on port ${_socket!.port}');
    return _socket!.port;
  }

  /// Ensure the socket is bound. If already bound, returns the existing port.
  Future<int> ensureBound() async {
    if (_socket != null) return _socket!.port;
    return bind();
  }

  void setStunResponseHandler(void Function(Datagram datagram)? handler) {
    _stunResponseHandler = handler;
  }

  /// Configure the STUN server used for keepalive packets.
  Future<void> setKeepaliveStunServer(String host, int port) async {
    _keepaliveStunPort = port;
    try {
      final addrs = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 3));
      final ipv4 = addrs.where((a) => a.type == InternetAddressType.IPv4);
      if (ipv4.isNotEmpty) {
        _keepaliveStunAddr = ipv4.first;
      }
    } catch (e) {
      AppLogger.warning(_tag, 'Failed to resolve keepalive STUN host: $e');
    }
    _startKeepaliveTimer();
    AppLogger.info(_tag, 'Keepalive configured: $host:$port');
  }

  /// Pause keepalive to avoid STUN response interference during queries.
  void pauseKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
  }

  /// Resume keepalive after queries complete.
  void resumeKeepalive() {
    if (_keepaliveStunAddr != null && _keepaliveStunPort != null) {
      _startKeepaliveTimer();
    }
  }

  /// Record that a packet was sent (called by StunService or internal sends).
  void recordSendTime() {
    _lastSendTime = DateTime.now();
  }

  /// Send a 1-byte random packet to the given address.
  void sendRawByte(String ip, int port) {
    if (_socket == null) return;
    final byte = Uint8List(1);
    byte[0] = _random.nextInt(pingMarker);
    try {
      _socket!.send(byte, InternetAddress(ip), port);
      _lastSendTime = DateTime.now();
    } catch (e) {
      AppLogger.error(_tag, 'Failed to send raw byte to $ip:$port', e);
    }
  }

  /// Send a ping packet: [0xFE][4B seq][8B timestamp_ms]
  void sendPing(String ip, int port, int seq) {
    if (_socket == null) return;
    final data = Uint8List(pingPacketSize);
    final bd = ByteData.sublistView(data);
    data[0] = pingMarker;
    bd.setUint32(1, seq);
    bd.setInt64(5, DateTime.now().millisecondsSinceEpoch);
    try {
      _socket!.send(data, InternetAddress(ip), port);
      _lastSendTime = DateTime.now();
    } catch (e) {
      AppLogger.error(_tag, 'Failed to send ping to $ip:$port', e);
    }
  }

  /// Echo a pong back (same payload, marker changed to 0xFF).
  void sendPong(String ip, int port, Uint8List pingData) {
    if (_socket == null) return;
    final data = Uint8List.fromList(pingData);
    data[0] = pongMarker;
    try {
      _socket!.send(data, InternetAddress(ip), port);
      _lastSendTime = DateTime.now();
    } catch (e) {
      AppLogger.error(_tag, 'Failed to send pong to $ip:$port', e);
    }
  }

  static bool _isStunMessage(Uint8List data) {
    if (data.length < 20) return false;
    return data[4] == 0x21 &&
        data[5] == 0x12 &&
        data[6] == 0xA4 &&
        data[7] == 0x42;
  }

  void _onData(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    // Drain all pending datagrams. On Android, a single read event may
    // correspond to multiple buffered datagrams, and no new event is fired
    // until the buffer is empty.
    Datagram? datagram;
    while ((datagram = _socket?.receive()) != null) {
      if (_isStunMessage(datagram!.data)) {
        _stunResponseHandler?.call(datagram);
      } else {
        onPeerPacketReceived?.call(
            datagram.address.address, datagram.port, datagram.data);
      }
    }
  }

  void _startKeepaliveTimer() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final elapsed = DateTime.now().difference(_lastSendTime);
      if (elapsed >= AppConstants.keepaliveTimeout) {
        _sendKeepalive();
      }
    });
  }

  void _sendKeepalive() {
    if (_keepaliveStunAddr == null || _keepaliveStunPort == null) return;
    if (_socket == null) return;
    final request = StunService.buildKeepaliveRequest();
    try {
      _socket!.send(request, _keepaliveStunAddr!, _keepaliveStunPort!);
      _lastSendTime = DateTime.now();
      AppLogger.debug(_tag, 'Sent keepalive STUN request');
    } catch (e) {
      AppLogger.warning(_tag, 'Keepalive send failed: $e');
    }
  }

  void close() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    _socket?.close();
    _socket = null;
    AppLogger.info(_tag, 'UDP socket closed');
  }
}
