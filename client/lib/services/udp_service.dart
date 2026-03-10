import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:p2p_test/config/constants.dart';
import 'package:p2p_test/models/peer_candidate.dart';
import 'package:p2p_test/utils/logger.dart';

abstract class UdpEventListener {
  void onMessage(
      String remoteAddr, String msgType, Map<String, dynamic> data);
}

class _PunchOperation {
  final Completer<bool> completer = Completer<bool>();
  final Set<String> targets;
  String? successAddr;

  _PunchOperation(this.targets);
}

class UdpService {
  static const String _tag = 'UdpService';

  RawDatagramSocket? _socket;
  UdpEventListener? _listener;
  void Function(Datagram datagram)? _stunResponseHandler;

  final Set<String> _connectedPeers = {};
  final List<_PunchOperation> _activePunchOps = [];

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
    _completePunchOps(addr);
  }

  void _handlePunchAck(String addr) {
    AppLogger.debug(_tag, 'Received punch_ack from $addr');
    _connectedPeers.add(addr);
    _completePunchOps(addr);
  }

  void _completePunchOps(String addr) {
    for (final op in _activePunchOps) {
      if (op.targets.contains(addr) && !op.completer.isCompleted) {
        op.successAddr = addr;
        op.completer.complete(true);
      }
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

  /// Attempt hole punch to multiple candidate addresses simultaneously.
  /// Returns the [PeerCandidate] that successfully connected, or null on timeout.
  /// Supports multiple concurrent operations without interference.
  Future<PeerCandidate?> holePunchMultiCandidate(
    List<PeerCandidate> candidates, {
    int? timeoutSec,
  }) async {
    final timeout =
        timeoutSec ?? AppConstants.holePunchTimeout.inSeconds;

    final targetAddrs = candidates.map((c) => c.address).toSet();

    for (final addr in targetAddrs) {
      if (_connectedPeers.contains(addr)) {
        final parts = addr.split(':');
        return PeerCandidate(parts[0], int.parse(parts[1]));
      }
    }

    final op = _PunchOperation(targetAddrs);
    _activePunchOps.add(op);

    void sendPunchToAll() {
      for (final candidate in candidates) {
        sendMessage(candidate.ip, candidate.port, 'punch', {
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
    }

    sendPunchToAll();

    final deadline = DateTime.now().add(Duration(seconds: timeout));

    Timer.periodic(AppConstants.holePunchInterval, (timer) {
      if (op.completer.isCompleted) {
        timer.cancel();
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        timer.cancel();
        if (!op.completer.isCompleted) {
          op.completer.complete(false);
        }
        return;
      }
      sendPunchToAll();
    });

    AppLogger.info(_tag,
        'Starting hole punch to ${candidates.map((c) => c.address).join(", ")}');

    final result = await op.completer.future;
    _activePunchOps.remove(op);

    if (result && op.successAddr != null) {
      final parts = op.successAddr!.split(':');
      final active = PeerCandidate(parts[0], int.parse(parts[1]));
      AppLogger.info(_tag, 'Hole punch succeeded via ${active.address}');
      return active;
    }

    AppLogger.warning(_tag, 'Hole punch timeout');
    return null;
  }

  /// Convenience wrapper: single-address hole punch (backward compatible).
  Future<bool> holePunch(String remoteIp, int remotePort,
      {int? timeoutSec}) async {
    final result = await holePunchMultiCandidate(
      [PeerCandidate(remoteIp, remotePort)],
      timeoutSec: timeoutSec,
    );
    return result != null;
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
    for (final op in _activePunchOps) {
      if (!op.completer.isCompleted) {
        op.completer.complete(false);
      }
    }
    _activePunchOps.clear();
    AppLogger.info(_tag, 'UDP socket closed');
  }
}
