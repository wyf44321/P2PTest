import 'dart:async';
import 'dart:io';
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

  /// True if the PEER is behind a symmetric NAT (port changes per dest).
  final bool isSymmetric;

  /// True if WE are behind a symmetric NAT. When true, main socket scanning
  /// must be suppressed — each packet to a different port burns a NAT
  /// allocation, destroying our own predictability.
  final bool ownIsSymmetric;

  final int portStep;
  final double portVelocity;
  final double probeTimestamp;

  /// Port parity from peer's NAT analysis: 0=even, 1=odd, -1=mixed/unknown
  final int portParity;

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

  /// When ownIsSymmetric + isSymmetric: main socket sends to this single
  /// port instead of scanning. Rotated slowly to avoid burning NAT ports.
  int? singleTargetPort;
  int singleTargetRotation = 0;

  // --- Birthday attack (multi-socket) for symmetric NAT ---
  final List<RawDatagramSocket> auxSockets = [];
  final List<int> auxTargetPorts = [];
  Timer? auxSendTimer;
  Timer? auxReshuffleTimer;

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
    this.ownIsSymmetric = false,
    required this.portStep,
    this.portVelocity = 0,
    this.probeTimestamp = 0,
    this.portParity = -1,
  })  : startedAt = DateTime.now(),
        privateCandidates =
            candidates.where((c) => Validators.isPrivateIp(c.ip)).toList(),
        publicCandidates =
            candidates.where((c) => !Validators.isPrivateIp(c.ip)).toList();

  /// True when both sides are symmetric — the hardest scenario.
  bool get bothSymmetric => isSymmetric && ownIsSymmetric;
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

  /// Our own NAT type: true if we are behind a symmetric NAT.
  /// Updated by the app layer after STUN analysis completes.
  bool _ownIsSymmetric = false;

  MonitorService({required this.udpService}) {
    udpService.onPeerPacketReceived = _onPacketReceived;
  }

  /// Called after our own NAT analysis completes so we can adapt sending
  /// strategy: when we are also symmetric, port scanning from the main socket
  /// must be stopped — each packet to a different destination port consumes a
  /// new external port allocation, making us unpredictable to the peer.
  void setOwnNatType(String? natMetadata) {
    final wasSym = _ownIsSymmetric;
    _ownIsSymmetric =
        natMetadata != null && natMetadata.startsWith('sym');
    if (wasSym != _ownIsSymmetric) {
      AppLogger.info(_tag,
          'Own NAT type updated: symmetric=$_ownIsSymmetric');
    }
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
    int portParity = -1;
    if (isSymmetric) {
      final meta = natMetadata;
      final stepMatch = RegExp(r'd=(\d+)').firstMatch(meta);
      if (stepMatch != null) {
        portStep = int.tryParse(stepMatch.group(1)!) ?? 1;
      }
      final velMatch = RegExp(r'v=(\d+)').firstMatch(meta);
      if (velMatch != null) {
        portVelocity = (int.tryParse(velMatch.group(1)!) ?? 0).toDouble();
      }
      final tsMatch = RegExp(r't=(\d+)').firstMatch(meta);
      if (tsMatch != null) {
        probeTimestamp = (int.tryParse(tsMatch.group(1)!) ?? 0).toDouble();
      }
      final parityMatch = RegExp(r'p=(\d+)').firstMatch(meta);
      if (parityMatch != null) {
        portParity = int.tryParse(parityMatch.group(1)!) ?? -1;
      }
    }

    final allPrivate = candidates.every((c) => Validators.isPrivateIp(c.ip));

    final peerSym = isSymmetric && !allPrivate;

    final state = _PeerSendState(
      peerId: peerId,
      candidates: candidates,
      targetIp: primary.ip,
      basePort: primary.port,
      isSymmetric: peerSym,
      ownIsSymmetric: _ownIsSymmetric,
      portStep: portStep,
      portVelocity: portVelocity,
      probeTimestamp: probeTimestamp,
      portParity: portParity,
    );

    _peerStates[peerId] = state;
    _startPrivateFallbackTimer(state);
    _startSendLoop(state);
    _startTimeoutChecker(state);
    _ensureStatsTimer();

    if (peerSym) {
      _setupBirthdaySockets(state);
    }

    final mode = state.bothSymmetric
        ? 'SYM↔SYM (birthday only, no main scanning)'
        : (peerSym
            ? 'CONE→SYM (scanning + birthday)'
            : (_ownIsSymmetric ? 'SYM→CONE (single target)' : 'CONE↔CONE'));

    AppLogger.info(_tag,
        'Started sending to $peerId [$mode] '
        'peerSym=$peerSym, ownSym=$_ownIsSymmetric, '
        'step=$portStep, velocity=${portVelocity.round()}p/s, '
        'parity=${portParity >= 0 ? (portParity == 0 ? "even" : "odd") : "mixed"}, '
        'probeTs=${probeTimestamp.round()}, '
        'birthday=${peerSym ? (state.bothSymmetric ? AppConstants.birthdaySocketCountSymSym : AppConstants.birthdaySocketCount) : 0}, '
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
      _closeBirthdaySockets(state);
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

    if (state.bothSymmetric) {
      // SYM↔SYM: main socket sends to ONE predicted port only.
      // Scanning many ports would burn our own NAT allocations, making us
      // unpredictable. Birthday sockets handle the broad coverage.
      _sendSingleTargetKeepalive(state);
      return;
    }

    if (state.isSymmetric) {
      if (state.ownIsSymmetric) {
        // SYM→SYM handled above, but defensive fallback
        _sendSingleTargetKeepalive(state);
      } else {
        // CONE→SYM: our port is stable, scanning is safe
        _sendSymmetricPrediction(state);
      }
      return;
    }

    if (state.ownIsSymmetric) {
      // SYM→CONE: peer port is known and stable, just send to it.
      // Don't scan — that wastes our NAT ports.
      for (final c in state.candidates) {
        udpService.sendRawByte(c.ip, c.port);
      }
      return;
    }

    // CONE↔CONE: simple case
    for (final c in state.candidates) {
      udpService.sendRawByte(c.ip, c.port);
    }
  }

  /// SYM↔SYM: send from main socket to a single predicted port.
  /// Rotated slowly (every ~100 cycles = 1 second) to avoid burning NAT ports
  /// while still probing different ports over time.
  void _sendSingleTargetKeepalive(_PeerSendState state) {
    final basePort = state.effectiveBasePort;
    final velocity = state.portVelocity;
    final probeTs = state.effectiveTimestamp;

    final nowSec = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final elapsedSec =
        probeTs > 0 ? (nowSec - probeTs).clamp(0.0, 600.0) : 0.0;
    final drift = velocity > 0 ? (velocity * elapsedSec).round() : 0;
    final center = (basePort + drift).clamp(1024, 65535);

    // Rotate target every ~100 cycles (1 second at 10ms interval)
    if (state.singleTargetPort == null ||
        state.sendCycleIndex % 100 == 0) {
      if (_isRandomAllocation(state)) {
        // Random allocation NAT: pick random port in ephemeral range
        state.singleTargetPort = 1024 + _random.nextInt(64512);
      } else {
        final step = max(1, state.portStep);
        final offset = state.singleTargetRotation * step;
        final raw = center + offset;
        if (raw > 65535) {
          state.singleTargetRotation = 0;
          state.singleTargetPort = center;
        } else {
          state.singleTargetPort = raw.clamp(1024, 65535);
        }
      }
      state.singleTargetRotation++;
    }

    state.sendCycleIndex++;
    udpService.sendRawByte(state.targetIp, state.singleTargetPort!);
  }

  /// Detect random-allocation NAT: step >= 100 indicates ports are
  /// essentially random, not sequentially allocated.
  static bool _isRandomAllocation(_PeerSendState state) =>
      state.portStep >= 100;

  /// Time-compensated, step-aligned, parity-aware port prediction for symmetric NAT.
  ///
  /// Key improvements over naive sequential scanning:
  ///
  /// 1. **Step-aligned**: Scans at multiples of the NAT's allocation step
  ///    (e.g., step=2 → only even/odd ports). This covers step× more range
  ///    with the same batch size.
  ///
  /// 2. **Parity-aware**: If the peer's NAT only allocates even (or odd)
  ///    ports, skips the other parity — effectively doubling useful range.
  ///
  /// 3. **Adaptive widening**: After many cycles without connection, gradually
  ///    widens the scan range to handle cases where velocity estimation
  ///    was inaccurate or background traffic caused unexpected drift.
  ///
  /// 4. **Birthday complement**: Works alongside auxiliary birthday sockets
  ///    (stable, single-target mappings) — the main socket does broad
  ///    scanning while birthday sockets provide anchored coverage.
  void _sendSymmetricPrediction(_PeerSendState state) {
    const batchSize = AppConstants.symmetricBatchSize;
    final basePort = state.effectiveBasePort;
    final velocity = state.portVelocity;
    final probeTs = state.effectiveTimestamp;
    final step = max(1, state.portStep);

    final nowSec = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final elapsedSec =
        probeTs > 0 ? (nowSec - probeTs).clamp(0.0, 600.0) : 0.0;

    final drift = velocity > 0 ? (velocity * elapsedSec).round() : 0;
    final center = basePort + drift;

    // Adaptive widening: expand radii after prolonged scanning without reply
    double widening = 1.0;
    final cycle = state.sendCycleIndex;
    if (cycle > AppConstants.symmetricWideningStartCycle) {
      final over = cycle - AppConstants.symmetricWideningStartCycle;
      widening = (1.0 + over / AppConstants.symmetricWideningDivisor)
          .clamp(1.0, AppConstants.symmetricMaxWidening);
    }

    // Hot zone: tight window around estimated center (step-aligned)
    final hotRadiusSteps =
        (AppConstants.symmetricHotRadius * widening).round();
    final hotStartPort = _alignPort(
        (center - hotRadiusSteps * step).clamp(1, 65535), basePort, step);
    final hotEndPort = (center + hotRadiusSteps * step).clamp(1, 65535);
    final hotSteps = max(1, (hotEndPort - hotStartPort) ~/ step);

    // Extended zone: wider coverage (step-aligned)
    final extRadiusRaw = velocity > 0
        ? (velocity * max(3.0, elapsedSec * 0.5))
            .round()
            .clamp(AppConstants.symmetricMinExtRadius,
                   AppConstants.symmetricMaxExtRadius)
        : AppConstants.symmetricFallbackRange;
    final extRadius = (extRadiusRaw * widening).round();
    final extStartPort = _alignPort(basePort, basePort, step);
    final extEndPort = (center + extRadius).clamp(1, 65535);
    final extSteps = max(1, (extEndPort - extStartPort) ~/ step);

    const hotBatch = (batchSize * 2) ~/ 3;
    const extBatch = batchSize - hotBatch;

    // Hot zone: sequential cycle through step-aligned ports
    final hotOffset = (cycle * hotBatch) % hotSteps;
    for (int i = 0; i < hotBatch; i++) {
      final port = hotStartPort + ((hotOffset + i) % hotSteps) * step;
      if (_matchesParity(port, state.portParity) &&
          port >= 1 && port <= 65535) {
        udpService.sendRawByte(state.targetIp, port);
      }
    }

    // Extended zone: sequential cycle through step-aligned ports
    final extOffset = (cycle * extBatch) % extSteps;
    for (int i = 0; i < extBatch; i++) {
      final port = extStartPort + ((extOffset + i) % extSteps) * step;
      if (_matchesParity(port, state.portParity) &&
          port >= 1 && port <= 65535) {
        udpService.sendRawByte(state.targetIp, port);
      }
    }

    state.sendCycleIndex++;

    udpService.sendRawByte(state.targetIp, basePort);
  }

  /// Align a port to the nearest step-multiple from the base,
  /// clamped to valid port range [1, 65535].
  static int _alignPort(int port, int base, int step) {
    if (step <= 1) return port.clamp(1, 65535);
    final offset = ((port - base) % step + step) % step;
    final aligned = offset == 0 ? port : port + (step - offset);
    if (aligned > 65535) return port - offset;
    return aligned.clamp(1, 65535);
  }

  /// Check if a port matches the expected parity (0=even, 1=odd, -1=any).
  static bool _matchesParity(int port, int parity) {
    if (parity < 0) return true;
    return (port % 2) == parity;
  }

  // --- Birthday attack: multi-socket for symmetric NAT ---
  //
  // Opens K auxiliary sockets, each targeting one predicted port on the peer.
  // Each socket creates exactly one stable NAT mapping (our_ext_port → peer:target).
  // The peer's scanning has K× more targets to hit, dramatically improving
  // collision probability for symmetric-to-symmetric NAT traversal.
  //
  // From the birthday paradox: with K sockets per side and port range R,
  // P(match) ≈ 1 - e^(-K²/R). For K=16, R=256: P ≈ 64%.

  final Random _random = Random();

  Future<void> _setupBirthdaySockets(_PeerSendState state) async {
    _closeBirthdaySockets(state);

    final count = state.bothSymmetric
        ? AppConstants.birthdaySocketCountSymSym
        : AppConstants.birthdaySocketCount;
    final targets = _pickBirthdayTargets(state, count);

    final bindAddr = state.targetIp.contains(':')
        ? InternetAddress.anyIPv6
        : InternetAddress.anyIPv4;

    for (int i = 0; i < count; i++) {
      try {
        final socket =
            await RawDatagramSocket.bind(bindAddr, 0);
        state.auxSockets.add(socket);
        state.auxTargetPorts.add(targets[i]);

        socket.listen((event) {
          if (event != RawSocketEvent.read) return;
          Datagram? dg;
          while ((dg = socket.receive()) != null) {
            _onAuxPacketReceived(state, dg!);
          }
        });
      } catch (e) {
        AppLogger.warning(_tag,
            'Peer ${state.peerId}: failed to open birthday socket #$i: $e');
        break;
      }
    }

    // Periodically send from each auxiliary socket to its target
    state.auxSendTimer?.cancel();
    state.auxSendTimer =
        Timer.periodic(AppConstants.birthdaySendInterval, (_) {
      if (state.connected || state.disconnected) return;
      _sendBirthdayPackets(state);
    });

    // Periodically reshuffle targets if still not connected
    state.auxReshuffleTimer?.cancel();
    state.auxReshuffleTimer =
        Timer.periodic(AppConstants.birthdayReshuffleInterval, (_) {
      if (state.connected || state.disconnected) return;
      _reshuffleBirthdayTargets(state);
    });

    AppLogger.info(_tag,
        'Peer ${state.peerId}: opened ${state.auxSockets.length} birthday sockets, '
        'targets=${targets.take(5).join(",")}...');
  }

  List<int> _pickBirthdayTargets(_PeerSendState state, int count) {
    // Random-allocation NAT (step >= 100): ports are essentially random.
    // Spread birthday sockets randomly across the full ephemeral port range.
    if (_isRandomAllocation(state)) {
      return _pickRandomBirthdayTargets(count);
    }

    final basePort = state.effectiveBasePort;
    final velocity = state.portVelocity;
    final probeTs = state.effectiveTimestamp;
    final step = max(1, state.portStep);

    final nowSec = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final elapsedSec =
        probeTs > 0 ? (nowSec - probeTs).clamp(0.0, 600.0) : 0.0;
    final drift = velocity > 0 ? (velocity * elapsedSec).round() : 0;
    final center = (basePort + drift).clamp(1024, 65535);

    final velocityRange =
        velocity > 0 ? (velocity * max(5.0, elapsedSec)).round() : 0;
    final range = max(
      count * step * 2,
      velocityRange.clamp(
          AppConstants.birthdayRangeMin, AppConstants.birthdayRangeMax),
    );

    final rangeStart = (center - range ~/ 4).clamp(1024, 65535);

    final targets = <int>[];
    final spacing = max(step, range ~/ count);
    for (int i = 0; i < count; i++) {
      var port = _alignPort(rangeStart + i * spacing, basePort, step);
      port = port.clamp(1024, 65535);
      if (!_matchesParity(port, state.portParity)) {
        port = (port + 1).clamp(1024, 65535);
      }
      targets.add(port);
    }
    return targets;
  }

  /// For random-allocation NATs: distribute sockets randomly across the
  /// full ephemeral port range (1024-65535). Each reshuffle picks entirely
  /// new random ports, maximizing coverage over time.
  List<int> _pickRandomBirthdayTargets(int count) {
    final targets = <int>[];
    final used = <int>{};
    for (int i = 0; i < count; i++) {
      int port;
      do {
        port = 1024 + _random.nextInt(64512);
      } while (used.contains(port));
      used.add(port);
      targets.add(port);
    }
    targets.sort();
    return targets;
  }

  void _sendBirthdayPackets(_PeerSendState state) {
    final targetAddr = InternetAddress(state.targetIp);
    final byte = Uint8List(1);

    for (int i = 0; i < state.auxSockets.length; i++) {
      if (i >= state.auxTargetPorts.length) break;
      byte[0] = _random.nextInt(UdpService.pingMarker);
      try {
        state.auxSockets[i].send(byte, targetAddr, state.auxTargetPorts[i]);
      } catch (_) {}
    }
  }

  void _reshuffleBirthdayTargets(_PeerSendState state) {
    final newTargets =
        _pickBirthdayTargets(state, state.auxSockets.length);
    state.auxTargetPorts.clear();
    state.auxTargetPorts.addAll(newTargets);
    AppLogger.debug(_tag,
        'Peer ${state.peerId}: reshuffled birthday targets → '
        '${newTargets.take(5).join(",")}...');
  }

  void _onAuxPacketReceived(_PeerSendState state, Datagram datagram) {
    final ip = datagram.address.address;
    final port = datagram.port;

    final isPing = datagram.data.length == UdpService.pingPacketSize &&
        datagram.data[0] == UdpService.pingMarker;
    if (isPing) {
      udpService.sendPong(ip, port, datagram.data);
    }

    if (!state.disconnected) {
      _handlePeerReply(state, ip, port);
    }
  }

  void _closeBirthdaySockets(_PeerSendState state) {
    state.auxSendTimer?.cancel();
    state.auxSendTimer = null;
    state.auxReshuffleTimer?.cancel();
    state.auxReshuffleTimer = null;
    for (final socket in state.auxSockets) {
      try {
        socket.close();
      } catch (_) {}
    }
    state.auxSockets.clear();
    state.auxTargetPorts.clear();
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
      _closeBirthdaySockets(state);
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

    // Re-open birthday sockets for the new reconnect attempt
    if (state.isSymmetric) {
      _setupBirthdaySockets(state);
    }

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
      // Close birthday sockets — no longer needed once connected
      _closeBirthdaySockets(state);
      updateActiveAddress?.call(state.peerId, ip, port);
      updatePeerStatus?.call(state.peerId, ConnectionStatus.connected);
      _startPingLoop(state);
      AppLogger.info(_tag,
          'Peer ${state.peerId} connected via $ip:$port');
    } else if (state.lockedIp != ip || state.lockedPort != port) {
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
      _closeBirthdaySockets(state);
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
