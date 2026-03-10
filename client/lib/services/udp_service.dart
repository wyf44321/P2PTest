import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:p2p_test/config/constants.dart';
import 'package:p2p_test/utils/logger.dart';

abstract class UdpEventListener {
  void onMessage(
      String remoteAddr, String msgType, Map<String, dynamic> data);
}

class UdpService {
  static const String _tag = 'UdpService';

  RawDatagramSocket? _socket;
  UdpEventListener? _listener;
  void Function(Datagram datagram)? _stunResponseHandler;

  final Set<String> _connectedPeers = {};
  Completer<bool>? _activePunchCompleter;
  String? _activePunchTarget;

  RawDatagramSocket? get socket => _socket;
  bool get isBound => _socket != null;
  Set<String> get connectedPeers => Set.unmodifiable(_connectedPeers);

  Future<int> bind({int port = 0}) async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    _socket!.listen(_onData);
    AppLogger.info(_tag, 'UDP socket bound on port ${_socket!.port}');
    return _socket!.port;
  }

  void setStunResponseHandler(void Function(Datagram datagram)? handler) {
    _stunResponseHandler = handler;
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
    final datagram = _socket?.receive();
    if (datagram == null) return;

    if (_isStunMessage(datagram.data) && _stunResponseHandler != null) {
      _stunResponseHandler!(datagram);
      return;
    }

    try {
      final data = utf8.decode(datagram.data);
      final msg = jsonDecode(data) as Map<String, dynamic>;
      final type = msg['type'] as String?;
      final addr = '${datagram.address.address}:${datagram.port}';

      if (type == null) {
        AppLogger.warning(_tag, 'Received message without type from $addr');
        return;
      }

      if (type == 'punch') {
        _handlePunchMessage(addr, datagram.address.address, datagram.port);
        return;
      }

      if (type == 'punch_ack') {
        _handlePunchAck(addr);
        return;
      }

      _listener?.onMessage(addr, type, msg);
    } catch (e) {
      AppLogger.error(_tag, 'Failed to parse UDP message', e);
    }
  }

  void _handlePunchMessage(String addr, String ip, int port) {
    AppLogger.debug(_tag, 'Received punch from $addr');
    _connectedPeers.add(addr);
    sendMessage(ip, port, 'punch_ack', {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    if (_activePunchTarget == addr &&
        _activePunchCompleter != null &&
        !_activePunchCompleter!.isCompleted) {
      _activePunchCompleter!.complete(true);
    }
  }

  void _handlePunchAck(String addr) {
    AppLogger.debug(_tag, 'Received punch_ack from $addr');
    _connectedPeers.add(addr);

    if (_activePunchTarget == addr &&
        _activePunchCompleter != null &&
        !_activePunchCompleter!.isCompleted) {
      _activePunchCompleter!.complete(true);
    }
  }

  void sendMessage(
      String ip, int port, String type, Map<String, dynamic> data) {
    if (_socket == null) {
      AppLogger.warning(_tag, 'Cannot send: socket not bound');
      return;
    }
    final msg = jsonEncode({...data, 'type': type});
    final bytes = utf8.encode(msg);
    try {
      _socket!.send(bytes, InternetAddress(ip), port);
    } catch (e) {
      AppLogger.error(_tag, 'Failed to send message to $ip:$port', e);
    }
  }

  Future<bool> holePunch(String remoteIp, int remotePort,
      {int? timeoutSec}) async {
    final timeout =
        timeoutSec ?? AppConstants.holePunchTimeout.inSeconds;
    final targetAddr = '$remoteIp:$remotePort';

    if (_connectedPeers.contains(targetAddr)) return true;

    _activePunchCompleter = Completer<bool>();
    _activePunchTarget = targetAddr;

    final deadline = DateTime.now().add(Duration(seconds: timeout));

    Timer.periodic(AppConstants.holePunchInterval, (timer) {
      if (_activePunchCompleter == null || _activePunchCompleter!.isCompleted) {
        timer.cancel();
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        timer.cancel();
        if (!_activePunchCompleter!.isCompleted) {
          _activePunchCompleter!.complete(false);
        }
        return;
      }
      sendMessage(remoteIp, remotePort, 'punch', {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    });

    AppLogger.info(_tag, 'Starting hole punch to $targetAddr');

    final result = await _activePunchCompleter!.future;
    _activePunchCompleter = null;
    _activePunchTarget = null;

    if (result) {
      AppLogger.info(_tag, 'Hole punch succeeded to $targetAddr');
    } else {
      AppLogger.warning(_tag, 'Hole punch timeout to $targetAddr');
    }

    return result;
  }

  bool isConnected(String ip, int port) {
    return _connectedPeers.contains('$ip:$port');
  }

  void markDisconnected(String ip, int port) {
    _connectedPeers.remove('$ip:$port');
  }

  void setEventListener(UdpEventListener listener) {
    _listener = listener;
  }

  void close() {
    _socket?.close();
    _socket = null;
    _connectedPeers.clear();
    AppLogger.info(_tag, 'UDP socket closed');
  }
}
