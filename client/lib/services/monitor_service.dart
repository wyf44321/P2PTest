import 'dart:async';
import 'dart:collection';

import 'package:p2p_test/config/constants.dart';
import 'package:p2p_test/models/monitored_peer.dart';
import 'package:p2p_test/models/peer_candidate.dart';
import 'package:p2p_test/services/udp_service.dart';
import 'package:p2p_test/utils/logger.dart';
import 'package:p2p_test/utils/reconnect.dart';

class PingRecord {
  final int seq;
  final int sentAt;
  bool received;
  int? rtt;

  PingRecord({required this.seq, required this.sentAt})
      : received = false;
}

class PingStats {
  final Queue<PingRecord> _pingHistory = Queue();

  void recordPingSent(int seq, int timestamp) {
    _pingHistory.addLast(PingRecord(seq: seq, sentAt: timestamp));
    while (_pingHistory.length > AppConstants.pingWindowSize) {
      _pingHistory.removeFirst();
    }
  }

  void recordPongReceived(int seq, int rtt) {
    for (final record in _pingHistory) {
      if (record.seq == seq) {
        record.rtt = rtt;
        record.received = true;
        break;
      }
    }
  }

  double calculatePacketLoss() {
    if (_pingHistory.isEmpty) return 0.0;
    final now = DateTime.now().millisecondsSinceEpoch;
    int lost = 0;
    int total = 0;
    for (final record in _pingHistory) {
      if (now - record.sentAt > AppConstants.pongTimeoutMs) {
        total++;
        if (!record.received) lost++;
      }
    }
    if (total == 0) return 0.0;
    return (lost / total) * 100.0;
  }

  void clear() {
    _pingHistory.clear();
  }
}

typedef PeerListGetter = List<MonitoredPeer> Function();
typedef PeerGetter = MonitoredPeer? Function(String peerId);
typedef StatusUpdater = void Function(String peerId, ConnectionStatus status);
typedef RttUpdater = void Function(String peerId, int rtt);
typedef PacketLossUpdater = void Function(String peerId, double packetLoss);
typedef ReconnectProgressUpdater = void Function(
    String peerId, int attempt, int maxAttempts);
typedef ActiveAddressUpdater = void Function(
    String peerId, String ip, int port);

class MonitorService implements UdpEventListener {
  static const String _tag = 'MonitorService';

  final UdpService udpService;

  PeerListGetter? getConnectedPeers;
  PeerListGetter? getAllPeers;
  PeerGetter? getPeer;
  StatusUpdater? updatePeerStatus;
  RttUpdater? updateRtt;
  PacketLossUpdater? updatePacketLoss;
  ReconnectProgressUpdater? updateReconnectProgress;
  ActiveAddressUpdater? updateActiveAddress;

  final Map<String, PingStats> _peerStats = {};
  Timer? _probeTimer;
  Timer? _statsTimer;
  final Map<String, Timer> _degradedTimers = {};
  final Map<String, ReconnectController> _reconnectControllers = {};
  int _currentIndex = 0;
  int _nextSeq = 0;

  final Map<String, int> _missedPongs = {};
  static const int _disconnectThreshold = 3;

  MonitorService({required this.udpService}) {
    udpService.setEventListener(this);
  }

  void startTimers() {
    _probeTimer?.cancel();
    _statsTimer?.cancel();

    _probeTimer = Timer.periodic(AppConstants.probeInterval, (_) {
      _probeNextPeer();
    });

    _statsTimer = Timer.periodic(AppConstants.packetLossCalcInterval, (_) {
      _calculateAllPacketLoss();
    });

    AppLogger.info(_tag, 'Monitoring timers started');
  }

  void startMonitoring(String peerId) {
    _peerStats[peerId] = PingStats();
    _missedPongs[peerId] = 0;
    AppLogger.debug(_tag, 'Started monitoring peer $peerId');
  }

  void stopMonitoring(String peerId) {
    _peerStats.remove(peerId);
    _missedPongs.remove(peerId);
    _cancelDegradedTimer(peerId);
    _cancelReconnect(peerId);
    AppLogger.debug(_tag, 'Stopped monitoring peer $peerId');
  }

  void _probeNextPeer() {
    final peers = getConnectedPeers?.call() ?? [];
    if (peers.isEmpty) return;

    _currentIndex = _currentIndex % peers.length;
    final peer = peers[_currentIndex];
    _sendPing(peer);
    _currentIndex++;
  }

  void _sendPing(MonitoredPeer peer) {
    final seq = _nextSeq++;
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    udpService.sendMessage(peer.effectiveIp, peer.effectivePort, 'ping', {
      'seq': seq,
      'timestamp': timestamp,
    });

    _peerStats[peer.id]?.recordPingSent(seq, timestamp);

    Timer(const Duration(milliseconds: AppConstants.pongTimeoutMs + 500), () {
      final stats = _peerStats[peer.id];
      if (stats == null) return;
      for (final record in stats._pingHistory) {
        if (record.seq == seq) {
          if (!record.received) {
            _onPingTimeout(peer.id);
          }
          break;
        }
      }
    });
  }

  void _onPingTimeout(String peerId) {
    final count = (_missedPongs[peerId] ?? 0) + 1;
    _missedPongs[peerId] = count;

    if (count >= _disconnectThreshold) {
      _missedPongs[peerId] = 0;
      _handlePeerDisconnected(peerId);
    }
  }

  void _handlePeerDisconnected(String peerId) {
    final peer = getPeer?.call(peerId);
    if (peer == null) return;
    if (peer.status == ConnectionStatus.reconnecting ||
        peer.status == ConnectionStatus.degradedMonitoring) {
      return;
    }

    AppLogger.warning(_tag, 'Peer $peerId disconnected, starting reconnect');
    updatePeerStatus?.call(peerId, ConnectionStatus.reconnecting);
    udpService.markDisconnected(peer.effectiveIp, peer.effectivePort);

    _startReconnect(peerId, peer.effectiveCandidates);
  }

  void _startReconnect(String peerId, List<PeerCandidate> candidates) {
    _cancelReconnect(peerId);

    final controller = ReconnectController(
      onReconnect: () async {
        final result = await udpService.holePunchMultiCandidate(candidates);
        if (result != null) {
          updateActiveAddress?.call(peerId, result.ip, result.port);
          return true;
        }
        return false;
      },
      onSuccess: () {
        AppLogger.info(_tag, 'Reconnect succeeded for $peerId');
        updatePeerStatus?.call(peerId, ConnectionStatus.connected);
        _missedPongs[peerId] = 0;
        startMonitoring(peerId);
      },
      onFailure: () {
        AppLogger.warning(
            _tag, 'Reconnect exhausted for $peerId, starting degraded monitoring');
        startDegradedMonitoring(peerId);
      },
      onAttemptUpdate: (attempt, max) {
        updateReconnectProgress?.call(peerId, attempt, max);
      },
    );

    _reconnectControllers[peerId] = controller;
    controller.start();
  }

  void _cancelReconnect(String peerId) {
    _reconnectControllers[peerId]?.cancel();
    _reconnectControllers.remove(peerId);
  }

  void startDegradedMonitoring(String peerId) {
    _cancelDegradedTimer(peerId);
    updatePeerStatus?.call(peerId, ConnectionStatus.degradedMonitoring);

    _degradedTimers[peerId] =
        Timer.periodic(AppConstants.degradedProbeInterval, (_) {
      final peer = getPeer?.call(peerId);
      if (peer != null) {
        _sendPing(peer);
      }
    });

    AppLogger.info(_tag, 'Started degraded monitoring for $peerId');
  }

  void _cancelDegradedTimer(String peerId) {
    _degradedTimers[peerId]?.cancel();
    _degradedTimers.remove(peerId);
  }

  void _calculateAllPacketLoss() {
    for (final entry in _peerStats.entries) {
      final loss = entry.value.calculatePacketLoss();
      updatePacketLoss?.call(entry.key, loss);
    }
  }

  void clearDisconnectedPeers(List<String> peerIds) {
    for (final peerId in peerIds) {
      stopMonitoring(peerId);
    }
  }

  @override
  void onMessage(
      String remoteAddr, String msgType, Map<String, dynamic> data) {
    switch (msgType) {
      case 'ping':
        _onPingReceived(remoteAddr, data);
        break;
      case 'pong':
        _onPongReceived(remoteAddr, data);
        break;
      default:
        AppLogger.debug(_tag, 'Unknown message type: $msgType from $remoteAddr');
    }
  }

  void _onPingReceived(String remoteAddr, Map<String, dynamic> data) {
    final parts = remoteAddr.split(':');
    if (parts.length != 2) return;
    final ip = parts[0];
    final port = int.tryParse(parts[1]);
    if (port == null) return;

    final seq = data['seq'] as int? ?? 0;
    final pingTimestamp = data['timestamp'] as int? ?? 0;

    udpService.sendMessage(ip, port, 'pong', {
      'seq': seq,
      'ping_timestamp': pingTimestamp,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _onPongReceived(String remoteAddr, Map<String, dynamic> data) {
    final seq = data['seq'] as int? ?? 0;
    final pingTimestamp = data['ping_timestamp'] as int? ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rtt = now - pingTimestamp;

    final allPeers = getAllPeers?.call() ?? [];
    MonitoredPeer? matchedPeer;
    for (final peer in allPeers) {
      if (peer.activeAddress == remoteAddr) {
        matchedPeer = peer;
        break;
      }
    }
    if (matchedPeer == null) return;

    _peerStats[matchedPeer.id]?.recordPongReceived(seq, rtt);
    _missedPongs[matchedPeer.id] = 0;
    updateRtt?.call(matchedPeer.id, rtt);

    if (matchedPeer.status == ConnectionStatus.degradedMonitoring) {
      AppLogger.info(
          _tag, 'Peer ${matchedPeer.id} recovered from degraded monitoring');
      _cancelDegradedTimer(matchedPeer.id);
      updatePeerStatus?.call(matchedPeer.id, ConnectionStatus.connected);
      startMonitoring(matchedPeer.id);
    }
  }

  void stopAll() {
    _probeTimer?.cancel();
    _statsTimer?.cancel();
    _probeTimer = null;
    _statsTimer = null;

    for (final timer in _degradedTimers.values) {
      timer.cancel();
    }
    _degradedTimers.clear();

    for (final controller in _reconnectControllers.values) {
      controller.cancel();
    }
    _reconnectControllers.clear();

    _peerStats.clear();
    _missedPongs.clear();
    _currentIndex = 0;

    AppLogger.info(_tag, 'All monitoring stopped');
  }
}
