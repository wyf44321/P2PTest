import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:p2p_test/config/constants.dart';
import 'package:p2p_test/models/monitored_peer.dart';
import 'package:p2p_test/models/peer_candidate.dart';
import 'package:p2p_test/services/udp_service.dart';
import 'package:p2p_test/utils/logger.dart';
import 'package:p2p_test/utils/validators.dart';

typedef PeerGetter = MonitoredPeer? Function(String peerId);
typedef StatusUpdater = void Function(String peerId, ConnectionStatus status);
typedef ReconnectProgressUpdater = void Function(
    String peerId, int attempt, int maxAttempts);
typedef ActiveAddressUpdater = void Function(
    String peerId, String ip, int port);
typedef IncomingPeerHandler = void Function(String ip, int port);
typedef StatsUpdater = void Function(
    String peerId, double? latencyMs, double? lossPercent);

class _PingEntry {
  final int seq;
  final int sendTimeMs;
  bool replied = false;

  _PingEntry(this.seq, this.sendTimeMs);
}

/// Per-peer send state that drives the 10ms sending loop.
class _PeerSendState {
  final String peerId;
  final List<PeerCandidate> candidates;
  final String targetIp;
  final int basePort;
  final bool isSymmetric;
  final int portStep;
  final double portVelocity;
  final double probeTimestamp;

  Timer? sendTimer;
  Timer? timeoutChecker;
  Timer? pingTimer;
  DateTime startedAt;
  DateTime? lastReplyAt;
  int reconnectAttempt = 0;
  bool connected = false;
  bool disconnected = false;

  /// Once a working address is found, lock on.
  String? lockedIp;
  int? lockedPort;

  /// Phased connection: try private (LAN) candidates first, fall back to public.
  final List<PeerCandidate> privateCandidates;
  final List<PeerCandidate> publicCandidates;
  bool publicFallbackEnabled = false;
  Timer? fallbackTimer;

  /// Cycles through the port range for symmetric NAT scanning.
  int sendCycleIndex = 0;

  // Ping/pong stats
  int nextPingSeq = 0;
  final List<_PingEntry> pingWindow = [];
  double? smoothedRtt;

  static const double _rttAlpha = 0.3;
  static const int _maxWindowSize = 40;
  static const int _lossCutoffMs = 3000;

  /// Updated on reconnect: use last locked port as new reference point
  /// so the prediction center shifts to the most recent known port.
  int? _reconnectBasePort;
  double? _reconnectTimestamp;

  int get effectiveBasePort => _reconnectBasePort ?? basePort;
  double get effectiveTimestamp => _reconnectTimestamp ?? probeTimestamp;

  _PeerSendState({
    required this.peerId,
    required this.candidates,
    required this.targetIp,
    required this.basePort,
    required this.isSymmetric,
    required this.portStep,
    this.portVelocity = 0,
    this.probeTimestamp = 0,
  })  : startedAt = DateTime.now(),
        privateCandidates =
            candidates.where((c) => Validators.isPrivateIp(c.ip)).toList(),
        publicCandidates =
            candidates.where((c) => !Validators.isPrivateIp(c.ip)).toList();
}

class MonitorService {
  static const String _tag = 'MonitorService';

  final UdpService udpService;

  PeerGetter? getPeer;
  StatusUpdater? updatePeerStatus;
  ReconnectProgressUpdater? updateReconnectProgress;
  ActiveAddressUpdater? updateActiveAddress;
  IncomingPeerHandler? onIncomingPeer;
  StatsUpdater? updatePeerStats;

  final Map<String, _PeerSendState> _peerStates = {};
  Timer? _statsTimer;

  MonitorService({required this.udpService}) {
    udpService.onPeerPacketReceived = _onPacketReceived;
  }

  /// Start sending to a peer immediately after adding.
  void startSending(
    String peerId, {
    required List<PeerCandidate> candidates,
    String? natMetadata,
  }) {
    stopSending(peerId);

    final primary = candidates.firstWhere(
      (c) => !Validators.isPrivateIp(c.ip),
      orElse: () => candidates.first,
    );

    final isSymmetric =
        natMetadata != null && natMetadata.startsWith('sym');
    int portStep = 1;
    double portVelocity = 0;
    double probeTimestamp = 0;
    if (isSymmetric) {
      final stepMatch = RegExp(r'd=(\d+)').firstMatch(natMetadata!);
      if (stepMatch != null) {
        portStep = int.tryParse(stepMatch.group(1)!) ?? 1;
      }
      final velMatch = RegExp(r'v=(\d+)').firstMatch(natMetadata!);
      if (velMatch != null) {
        portVelocity = (int.tryParse(velMatch.group(1)!) ?? 0).toDouble();
      }
      final tsMatch = RegExp(r't=(\d+)').firstMatch(natMetadata!);
      if (tsMatch != null) {
        probeTimestamp = (int.tryParse(tsMatch.group(1)!) ?? 0).toDouble();
      }
    }

    final allPrivate = candidates.every((c) => Validators.isPrivateIp(c.ip));

    final state = _PeerSendState(
      peerId: peerId,
      candidates: candidates,
      targetIp: primary.ip,
      basePort: primary.port,
      isSymmetric: isSymmetric && !allPrivate,
      portStep: portStep,
      portVelocity: portVelocity,
      probeTimestamp: probeTimestamp,
    );

    _peerStates[peerId] = state;
    _startPrivateFallbackTimer(state);
    _startSendLoop(state);
    _startTimeoutChecker(state);
    _ensureStatsTimer();

    AppLogger.info(_tag,
        'Started sending to $peerId (symmetric=${state.isSymmetric}, '
        'step=$portStep, velocity=${portVelocity.round()}p/s, '
        'probeTs=${probeTimestamp.round()}, '
        'lan=${state.privateCandidates.length}, '
        'wan=${state.publicCandidates.length})');
  }

  /// Resume sending to a connected peer (e.g., after discovering active address).
  void startConnectedSending(String peerId, String ip, int port) {
    final existing = _peerStates[peerId];
    if (existing != null) {
      existing.connected = true;
      existing.lockedIp = ip;
      existing.lockedPort = port;
      existing.lastReplyAt = DateTime.now();
      existing.reconnectAttempt = 0;
      _startPingLoop(existing);
      return;
    }

    final state = _PeerSendState(
      peerId: peerId,
      candidates: [PeerCandidate(ip, port)],
      targetIp: ip,
      basePort: port,
      isSymmetric: false,
      portStep: 1,
    );
    state.connected = true;
    state.lockedIp = ip;
    state.lockedPort = port;
    state.lastReplyAt = DateTime.now();

    _peerStates[peerId] = state;
    _startSendLoop(state);
    _startTimeoutChecker(state);
    _startPingLoop(state);
    _ensureStatsTimer();
  }

  void stopSending(String peerId) {
    final state = _peerStates.remove(peerId);
    if (state != null) {
      state.sendTimer?.cancel();
      state.timeoutChecker?.cancel();
      state.pingTimer?.cancel();
      state.fallbackTimer?.cancel();
      AppLogger.debug(_tag, 'Stopped sending to $peerId');
    }
    if (_peerStates.isEmpty) {
      _statsTimer?.cancel();
      _statsTimer = null;
    }
  }

  void _startSendLoop(_PeerSendState state) {
    state.sendTimer?.cancel();
    state.sendTimer =
        Timer.periodic(AppConstants.peerSendInterval, (_) {
      if (state.disconnected) return;
      _sendToPeer(state);
    });
  }

  /// Start a timer that enables public candidate fallback after a delay.
  /// If no private candidates exist, public fallback is enabled immediately.
  void _startPrivateFallbackTimer(_PeerSendState state) {
    state.fallbackTimer?.cancel();
    state.fallbackTimer = null;
    if (state.privateCandidates.isEmpty) {
      state.publicFallbackEnabled = true;
      return;
    }
    state.publicFallbackEnabled = false;
    if (state.publicCandidates.isNotEmpty) {
      state.fallbackTimer =
          Timer(AppConstants.privatePhaseDuration, () {
        if (!state.connected && !state.disconnected) {
          state.publicFallbackEnabled = true;
          AppLogger.info(_tag,
              'Peer ${state.peerId}: LAN phase timeout, adding public addresses');
        }
      });
    }
  }

  void _sendToPeer(_PeerSendState state) {
    if (state.lockedPort != null) {
      udpService.sendRawByte(
          state.lockedIp ?? state.targetIp, state.lockedPort!);
      return;
    }

    // Private-first phase: only probe LAN candidates before fallback timer fires.
    if (!state.publicFallbackEnabled &&
        state.privateCandidates.isNotEmpty) {
      for (final c in state.privateCandidates) {
        udpService.sendRawByte(c.ip, c.port);
      }
      return;
    }

    if (state.isSymmetric) {
      _sendSymmetricPrediction(state);
      return;
    }

    for (final c in state.candidates) {
      udpService.sendRawByte(c.ip, c.port);
    }
  }

  /// Time-compensated dual-zone port prediction for symmetric NAT.
  ///
  /// Uses three features from the STUN probe:
  /// - **basePort**: last observed public port (reference point)
  /// - **velocity**: port consumption rate (ports/second)
  /// - **probeTimestamp**: when the probe completed (epoch seconds)
  ///
  /// The algorithm estimates the current port position based on elapsed
  /// time since the probe, then scans two zones with different priorities:
  /// - **Hot zone** (center ± hotRadius): dense scanning, 2/3 of batch
  /// - **Extended zone** (basePort → center + extRadius): wider coverage, 1/3 of batch
  ///
  /// NAT ports are monotonically increasing, so scanning is forward-biased.
  /// The hot zone follows the estimated center as it drifts forward over
  /// time, keeping the highest-probability ports under constant coverage.
  void _sendSymmetricPrediction(_PeerSendState state) {
    final batchSize = AppConstants.symmetricBatchSize;
    final basePort = state.effectiveBasePort;
    final velocity = state.portVelocity;
    final probeTs = state.effectiveTimestamp;

    final nowSec = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final elapsedSec =
        probeTs > 0 ? (nowSec - probeTs).clamp(0.0, 600.0) : 0.0;

    // Estimate where the port likely is now
    final drift = velocity > 0 ? (velocity * elapsedSec).round() : 0;
    final center = basePort + drift;

    // Hot zone: tight window around estimated center
    final hotRadius = AppConstants.symmetricHotRadius;
    final hotStart = (center - hotRadius).clamp(basePort, 65535);
    final hotEnd = (center + hotRadius).clamp(1, 65535);
    final hotSize = max(1, hotEnd - hotStart);

    // Extended zone: covers full possible range for higher uncertainty
    final extRadius = velocity > 0
        ? (velocity * max(3.0, elapsedSec * 0.5))
            .round()
            .clamp(AppConstants.symmetricMinExtRadius,
                   AppConstants.symmetricMaxExtRadius)
        : AppConstants.symmetricFallbackRange;
    final extStart = basePort;
    final extEnd = (center + extRadius).clamp(1, 65535);
    final extSize = max(1, extEnd - extStart);

    // Split batch: 2/3 hot zone, 1/3 extended zone
    final hotBatch = (batchSize * 2) ~/ 3;
    final extBatch = batchSize - hotBatch;

    // Hot zone: sequential cycle for dense coverage near center
    final hotOffset = (state.sendCycleIndex * hotBatch) % hotSize;
    for (int i = 0; i < hotBatch; i++) {
      final port = hotStart + ((hotOffset + i) % hotSize);
      if (port >= 1 && port <= 65535) {
        udpService.sendRawByte(state.targetIp, port);
      }
    }

    // Extended zone: sequential cycle for broad coverage
    final extOffset = (state.sendCycleIndex * extBatch) % extSize;
    for (int i = 0; i < extBatch; i++) {
      final port = extStart + ((extOffset + i) % extSize);
      if (port >= 1 && port <= 65535) {
        udpService.sendRawByte(state.targetIp, port);
      }
    }

    state.sendCycleIndex++;

    // Always probe basePort itself as anchor
    udpService.sendRawByte(state.targetIp, basePort);
  }

  void _startTimeoutChecker(_PeerSendState state) {
    state.timeoutChecker?.cancel();
    state.timeoutChecker =
        Timer.periodic(const Duration(seconds: 1), (_) {
      _checkTimeout(state);
    });
  }

  void _checkTimeout(_PeerSendState state) {
    if (state.disconnected) return;

    final refTime = state.lastReplyAt ?? state.startedAt;
    final elapsed = DateTime.now().difference(refTime);

    if (elapsed < AppConstants.peerReplyTimeout) return;

    state.reconnectAttempt++;
    AppLogger.warning(_tag,
        'Peer ${state.peerId} timeout, reconnect attempt ${state.reconnectAttempt}/${AppConstants.maxReconnectAttempts}');

    if (state.reconnectAttempt > AppConstants.maxReconnectAttempts) {
      state.disconnected = true;
      state.sendTimer?.cancel();
      state.timeoutChecker?.cancel();
      state.pingTimer?.cancel();
      updatePeerStatus?.call(state.peerId, ConnectionStatus.disconnected);
      AppLogger.warning(_tag, 'Peer ${state.peerId} disconnected after max retries');
      return;
    }

    // For symmetric NAT: use last locked port as new prediction reference
    // so the scan window shifts to the most recent known position.
    if (state.isSymmetric && state.lockedPort != null) {
      state._reconnectBasePort = state.lockedPort;
      state._reconnectTimestamp =
          DateTime.now().millisecondsSinceEpoch / 1000.0;
      state.sendCycleIndex = 0;
    }

    state.connected = false;
    state.lockedIp = null;
    state.lockedPort = null;
    state.pingTimer?.cancel();
    state.pingWindow.clear();
    state.smoothedRtt = null;
    state.startedAt = DateTime.now();
    state.lastReplyAt = null;
    _startPrivateFallbackTimer(state);

    updatePeerStatus?.call(state.peerId, ConnectionStatus.reconnecting);
    updateReconnectProgress?.call(
        state.peerId, state.reconnectAttempt, AppConstants.maxReconnectAttempts);
  }

  void _onPacketReceived(String ip, int port, Uint8List data) {
    final isPing = data.length == UdpService.pingPacketSize &&
        data[0] == UdpService.pingMarker;
    final isPong = data.length == UdpService.pingPacketSize &&
        data[0] == UdpService.pongMarker;

    if (isPing) {
      udpService.sendPong(ip, port, data);
    }

    final state = _findMatchingState(ip, port);
    if (state != null) {
      if (isPong) _processPong(state, data);
      _handlePeerReply(state, ip, port);
    } else {
      onIncomingPeer?.call(ip, port);
    }
  }

  _PeerSendState? _findMatchingState(String ip, int port) {
    for (final state in _peerStates.values) {
      if (state.disconnected) continue;
      if (state.lockedPort != null &&
          state.lockedIp == ip &&
          state.lockedPort == port) {
        return state;
      }
      if (state.candidates.any((c) => c.ip == ip && c.port == port)) {
        return state;
      }
    }
    for (final state in _peerStates.values) {
      if (state.disconnected) continue;
      if (state.candidates.any((c) => c.ip == ip)) {
        return state;
      }
    }
    // Same source port from private IPs = multi-homed peer
    if (Validators.isPrivateIp(ip)) {
      for (final state in _peerStates.values) {
        if (state.disconnected) continue;
        if (state.lockedPort == port &&
            state.lockedIp != null &&
            Validators.isPrivateIp(state.lockedIp!)) {
          return state;
        }
      }
    }
    return null;
  }

  void _handlePeerReply(_PeerSendState state, String ip, int port) {
    state.lastReplyAt = DateTime.now();

    if (!state.connected) {
      state.connected = true;
      state.reconnectAttempt = 0;
      state.lockedIp = ip;
      state.lockedPort = port;
      state.fallbackTimer?.cancel();
      state.pingWindow.clear();
      state.smoothedRtt = null;
      updateActiveAddress?.call(state.peerId, ip, port);
      updatePeerStatus?.call(state.peerId, ConnectionStatus.connected);
      _startPingLoop(state);
      AppLogger.info(_tag,
          'Peer ${state.peerId} connected via $ip:$port');
    } else if (state.lockedIp != ip || state.lockedPort != port) {
      // Don't switch locked address between private IPs of a multi-homed peer.
      final samePrivatePort = state.lockedPort == port &&
          state.lockedIp != null &&
          Validators.isPrivateIp(state.lockedIp!) &&
          Validators.isPrivateIp(ip);
      if (!samePrivatePort) {
        state.lockedIp = ip;
        state.lockedPort = port;
        updateActiveAddress?.call(state.peerId, ip, port);
      }
    }
  }

  void stopAll() {
    for (final state in _peerStates.values) {
      state.sendTimer?.cancel();
      state.timeoutChecker?.cancel();
      state.pingTimer?.cancel();
      state.fallbackTimer?.cancel();
    }
    _peerStates.clear();
    _statsTimer?.cancel();
    _statsTimer = null;
    AppLogger.info(_tag, 'All monitoring stopped');
  }

  // --- Ping / pong / stats ---

  void _startPingLoop(_PeerSendState state) {
    state.pingTimer?.cancel();
    state.pingTimer =
        Timer.periodic(AppConstants.pingInterval, (_) {
      if (!state.connected || state.disconnected) return;
      if (state.lockedPort == null) return;
      _sendPing(state);
    });
  }

  void _sendPing(_PeerSendState state) {
    final seq = state.nextPingSeq++;
    state.pingWindow.add(_PingEntry(seq, DateTime.now().millisecondsSinceEpoch));
    while (state.pingWindow.length > _PeerSendState._maxWindowSize) {
      state.pingWindow.removeAt(0);
    }
    udpService.sendPing(
        state.lockedIp ?? state.targetIp, state.lockedPort!, seq);
  }

  void _processPong(_PeerSendState state, Uint8List data) {
    final bd = ByteData.sublistView(data);
    final seq = bd.getUint32(1);
    final sendTimeMs = bd.getInt64(5);
    final now = DateTime.now().millisecondsSinceEpoch;
    final rtt = (now - sendTimeMs).toDouble();

    if (rtt < 0 || rtt > 30000) return;

    state.smoothedRtt = state.smoothedRtt == null
        ? rtt
        : state.smoothedRtt! * (1 - _PeerSendState._rttAlpha) +
            rtt * _PeerSendState._rttAlpha;

    for (final entry in state.pingWindow) {
      if (entry.seq == seq) {
        entry.replied = true;
        break;
      }
    }
  }

  double? _calculateLoss(_PeerSendState state) {
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - _PeerSendState._lossCutoffMs;
    final eligible =
        state.pingWindow.where((e) => e.sendTimeMs < cutoff).toList();
    if (eligible.isEmpty) return null;
    final lost = eligible.where((e) => !e.replied).length;
    return (lost / eligible.length) * 100.0;
  }

  void _ensureStatsTimer() {
    _statsTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      _reportAllStats();
    });
  }

  void _reportAllStats() {
    for (final state in _peerStates.values) {
      if (!state.connected || state.disconnected) continue;
      final latency = state.smoothedRtt;
      final loss = _calculateLoss(state);
      if (latency != null || loss != null) {
        updatePeerStats?.call(state.peerId, latency, loss);
      }
    }
  }
}
