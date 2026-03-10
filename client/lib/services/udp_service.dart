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
  void Function(String ip, int port)? onIncomingPeerConnected;

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
    AppLogger.info(_tag, 'Received punch from $addr');
    final isNew = !_connectedPeers.contains(addr);
    _connectedPeers.add(addr);
    sendMessage(ip, port, 'punch_ack', {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    final matched = _completePunchOps(addr, ip);
    if (isNew && !matched) {
      onIncomingPeerConnected?.call(ip, port);
    }
  }

  void _handlePunchAck(String addr) {
    final ip = addr.split(':').first;
    AppLogger.info(_tag, 'Received punch_ack from $addr');
    _connectedPeers.add(addr);
    _completePunchOps(addr, ip);
  }

  bool _completePunchOps(String addr, String ip) {
    for (final op in _activePunchOps) {
      if (op.completer.isCompleted) continue;

      // Exact match (including predicted ports).
      if (op.targets.contains(addr)) {
        op.successAddr = addr;
        op.completer.complete(true);
        return true;
      }

      // IP-only match: the peer is behind symmetric NAT so the actual source
      // port differs from the STUN-reported port. Accept any port from a
      // target IP we are actively punching.
      final targetIps = op.targets.map((a) => a.split(':').first).toSet();
      if (targetIps.contains(ip)) {
        AppLogger.info(_tag,
            'Accepted punch from $addr via IP-only match (symmetric NAT)');
        op.successAddr = addr;
        op.completer.complete(true);
        return true;
      }
    }
    return false;
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
  /// When [enablePortPrediction] is true, predicted ports around each candidate
  /// are tried after [AppConstants.portPredictionDelay].
  /// [isConsistentDelta] controls whether a narrow (delta-step) or wide
  /// (sequential scan) prediction range is used.
  Future<PeerCandidate?> holePunchMultiCandidate(
    List<PeerCandidate> candidates, {
    int? timeoutSec,
    bool enablePortPrediction = false,
    int? portDelta,
    bool isConsistentDelta = false,
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

    // When port prediction is active, also accept connections from predicted
    // ports so that _completePunchOps can match them.
    final predictedCandidates = enablePortPrediction
        ? _buildPredictedCandidates(candidates, portDelta,
            isConsistentDelta: isConsistentDelta)
        : <PeerCandidate>[];
    final allTargetAddrs = {
      ...targetAddrs,
      ...predictedCandidates.map((c) => c.address),
    };

    final op = _PunchOperation(allTargetAddrs);
    _activePunchOps.add(op);

    void sendPunchToAll() {
      for (final candidate in candidates) {
        sendMessage(candidate.ip, candidate.port, 'punch', {
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
    }

    void sendPunchToPredicted() {
      final ts = DateTime.now().millisecondsSinceEpoch;
      for (final candidate in predictedCandidates) {
        sendMessage(candidate.ip, candidate.port, 'punch', {
          'timestamp': ts,
        });
      }
    }

    sendPunchToAll();

    final deadline = DateTime.now().add(Duration(seconds: timeout));
    final predictionStart =
        DateTime.now().add(AppConstants.portPredictionDelay);

    int punchCount = 0;
    int predictedPunchCount = 0;

    Timer.periodic(AppConstants.holePunchInterval, (timer) {
      if (op.completer.isCompleted) {
        timer.cancel();
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        timer.cancel();
        AppLogger.warning(_tag,
            'Hole punch deadline reached after $punchCount rounds '
            '(predicted: $predictedPunchCount rounds)');
        if (!op.completer.isCompleted) {
          op.completer.complete(false);
        }
        return;
      }
      punchCount++;
      sendPunchToAll();
      if (enablePortPrediction && DateTime.now().isAfter(predictionStart)) {
        predictedPunchCount++;
        sendPunchToPredicted();
      }
    });

    final logMsg = enablePortPrediction
        ? 'Starting hole punch (port prediction ON, '
            'delta=${portDelta ?? "auto"}, '
            'consistent=$isConsistentDelta, '
            'predicted ports: ${predictedCandidates.length}) to '
            '${candidates.map((c) => c.address).join(", ")}'
        : 'Starting hole punch to ${candidates.map((c) => c.address).join(", ")}';
    AppLogger.info(_tag, logMsg);

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

  /// Build extra candidates around each original candidate for port prediction.
  ///
  /// Strategy adapts based on NAT allocation pattern:
  /// - **Consistent delta**: step in multiples of [portDelta] with a narrow
  ///   range – higher confidence, fewer packets.
  /// - **Inconsistent / unknown delta**: combine delta-step guesses with a
  ///   sequential ±1 scan over a wider range.
  static List<PeerCandidate> _buildPredictedCandidates(
    List<PeerCandidate> originals,
    int? portDelta, {
    bool isConsistentDelta = false,
  }) {
    final result = <PeerCandidate>{};

    void addIfValid(String ip, int port) {
      if (port > 0 && port <= 65535) result.add(PeerCandidate(ip, port));
    }

    for (final c in originals) {
      if (portDelta != null && portDelta != 0 && isConsistentDelta) {
        // --- Consistent allocation: focused delta-step prediction ---
        final range = AppConstants.portPredictionRangeConsistent;
        final step = portDelta.abs();
        final sign = portDelta > 0 ? 1 : -1;
        for (int i = 1; i <= range; i++) {
          addIfValid(c.ip, c.port + sign * step * i);
          addIfValid(c.ip, c.port - sign * step * i);
        }
      } else if (portDelta != null && portDelta != 0) {
        // --- Inconsistent allocation: delta guesses + sequential scan ---
        final range = AppConstants.portPredictionRangeWide;
        final step = portDelta.abs();

        // Delta-based predictions (higher priority candidates).
        for (int i = 1; i <= range ~/ 2; i++) {
          addIfValid(c.ip, c.port + step * i);
          addIfValid(c.ip, c.port - step * i);
        }
        // Fill in with sequential ±1 scan to cover irregular jumps.
        for (int d = 1; d <= range; d++) {
          addIfValid(c.ip, c.port + d);
          addIfValid(c.ip, c.port - d);
        }
      } else {
        // --- No delta info: pure sequential scan ---
        final range = AppConstants.portPredictionRangeWide;
        for (int d = 1; d <= range; d++) {
          addIfValid(c.ip, c.port + d);
          addIfValid(c.ip, c.port - d);
        }
      }
    }

    final originalAddrs = originals.map((c) => c.address).toSet();
    result.removeWhere((c) => originalAddrs.contains(c.address));
    return result.toList();
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
