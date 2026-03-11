import 'package:flutter/foundation.dart';

import 'package:p2p_test/models/monitored_peer.dart';
import 'package:p2p_test/models/peer_candidate.dart';
import 'package:p2p_test/services/ip_geo_service.dart';
import 'package:p2p_test/services/monitor_service.dart';
import 'package:p2p_test/utils/logger.dart';
import 'package:p2p_test/utils/validators.dart'
    show ParsedCandidateInput, Validators;

class PeerProvider extends ChangeNotifier {
  static const String _tag = 'PeerProvider';

  final MonitorService _monitorService;
  final IpGeoService _ipGeoService;

  List<MonitoredPeer> _peers = [];

  PeerProvider({
    required MonitorService monitorService,
    required IpGeoService ipGeoService,
  })  : _monitorService = monitorService,
        _ipGeoService = ipGeoService {
    _setupMonitorCallbacks();
  }

  List<MonitoredPeer> get peers => List.unmodifiable(_peers);

  bool get hasDisconnectedPeers => _peers.any(
        (p) =>
            p.status == ConnectionStatus.disconnected ||
            p.status == ConnectionStatus.failed,
      );

  void _setupMonitorCallbacks() {
    _monitorService.getPeer = (id) {
      try {
        return _peers.firstWhere((p) => p.id == id);
      } catch (_) {
        return null;
      }
    };
    _monitorService.updatePeerStatus = updatePeerStatus;
    _monitorService.updateReconnectProgress = updateReconnectProgress;
    _monitorService.updateActiveAddress = updateActiveAddress;
    _monitorService.onIncomingPeer = _onIncomingPeerConnected;
    _monitorService.updatePeerStats = updatePeerStats;
  }

  Future<void> addPeer(ParsedCandidateInput input) async {
    final candidates = input.candidates;
    if (candidates.isEmpty) return;

    final primary = candidates.firstWhere(
      (c) => !Validators.isPrivateIp(c.ip),
      orElse: () => candidates.first,
    );

    final id =
        '${primary.ip}_${primary.port}_${DateTime.now().millisecondsSinceEpoch}';
    final peer = MonitoredPeer(
      id: id,
      ip: primary.ip,
      port: primary.port,
      candidates: candidates,
      createdAt: DateTime.now(),
      status: ConnectionStatus.connecting,
      natMetadata: input.natMetadata,
    );

    _peers = [..._peers, peer];
    notifyListeners();

    _queryIpLocation(id, primary.ip);

    _monitorService.startSending(
      id,
      candidates: candidates,
      natMetadata: input.natMetadata,
    );
  }

  void removePeer(String peerId) {
    final peer = _findPeer(peerId);
    if (peer == null) return;

    _monitorService.stopSending(peerId);

    _peers = _peers.where((p) => p.id != peerId).toList();
    notifyListeners();

    AppLogger.info(_tag, 'Removed peer $peerId');
  }

  void clearDisconnectedPeers() {
    final toRemove = _peers
        .where((p) =>
            p.status == ConnectionStatus.disconnected ||
            p.status == ConnectionStatus.failed)
        .map((p) => p.id)
        .toList();

    if (toRemove.isEmpty) return;

    for (final peerId in toRemove) {
      _monitorService.stopSending(peerId);
    }

    _peers = _peers
        .where((p) =>
            p.status != ConnectionStatus.disconnected &&
            p.status != ConnectionStatus.failed)
        .toList();
    notifyListeners();

    AppLogger.info(_tag, 'Cleared ${toRemove.length} disconnected peers');
  }

  void updatePeerStatus(String peerId, ConnectionStatus status) {
    _updatePeer(peerId, (p) {
      if (status == ConnectionStatus.connected) {
        return p.copyWith(
          status: status,
          lastConnectedAt: DateTime.now(),
          reconnectCount: 0,
          clearStats: true,
        );
      }
      if (status == ConnectionStatus.reconnecting ||
          status == ConnectionStatus.disconnected) {
        return p.copyWith(status: status, clearStats: true);
      }
      return p.copyWith(status: status);
    });
  }

  void updatePeerStats(String peerId, double? latencyMs, double? lossPercent) {
    _updatePeer(
        peerId,
        (p) => p.copyWith(
              latencyMs: latencyMs,
              packetLossPercent: lossPercent,
            ));
  }

  void updateReconnectProgress(String peerId, int attempt, int maxAttempts) {
    _updatePeer(
        peerId, (p) => p.copyWith(reconnectCount: attempt));
  }

  void updateIpLocation(String peerId, String location) {
    _updatePeer(peerId, (p) => p.copyWith(ipLocation: location));
  }

  void updateActiveAddress(String peerId, String ip, int port) {
    _updatePeer(peerId, (p) => p.copyWith(activeIp: ip, activePort: port));
  }

  bool peerExists(ParsedCandidateInput input) {
    final newAddrs = input.candidates.map((c) => c.address).toSet();
    return _peers.any((p) {
      final existingAddrs =
          p.effectiveCandidates.map((c) => c.address).toSet();
      return existingAddrs.intersection(newAddrs).isNotEmpty;
    });
  }

  // --- Private helpers ---

  void _onIncomingPeerConnected(String ip, int port) {
    final addr = '$ip:$port';

    MonitoredPeer? existing;
    for (final p in _peers) {
      if (p.activeAddress == addr ||
          p.address == addr ||
          p.effectiveCandidates.any((c) => c.address == addr) ||
          p.effectiveIp == ip) {
        existing = p;
        break;
      }
    }

    // Same source port from private IPs = same peer with multiple interfaces
    if (existing == null && Validators.isPrivateIp(ip)) {
      for (final p in _peers) {
        if (p.effectivePort == port &&
            Validators.isPrivateIp(p.effectiveIp)) {
          existing = p;
          break;
        }
      }
    }

    if (existing != null) {
      if (existing.status != ConnectionStatus.connected) {
        updateActiveAddress(existing.id, ip, port);
        updatePeerStatus(existing.id, ConnectionStatus.connected);
        _monitorService.startConnectedSending(existing.id, ip, port);
        AppLogger.info(_tag,
            'Reconnected existing peer ${existing.id} via incoming packet from $addr');
      }
      return;
    }

    final id = '${ip}_${port}_${DateTime.now().millisecondsSinceEpoch}';
    final peer = MonitoredPeer(
      id: id,
      ip: ip,
      port: port,
      candidates: [PeerCandidate(ip, port)],
      activeIp: ip,
      activePort: port,
      createdAt: DateTime.now(),
      lastConnectedAt: DateTime.now(),
      status: ConnectionStatus.connected,
    );

    _peers = [..._peers, peer];
    notifyListeners();

    _queryIpLocation(id, ip);
    _monitorService.startConnectedSending(id, ip, port);

    AppLogger.info(_tag, 'Auto-added incoming peer $addr');
  }

  MonitoredPeer? _findPeer(String peerId) {
    try {
      return _peers.firstWhere((p) => p.id == peerId);
    } catch (_) {
      return null;
    }
  }

  void _updatePeer(
      String peerId, MonitoredPeer Function(MonitoredPeer) updater) {
    final index = _peers.indexWhere((p) => p.id == peerId);
    if (index == -1) return;
    _peers = List.from(_peers);
    _peers[index] = updater(_peers[index]);
    notifyListeners();
  }

  Future<void> _queryIpLocation(String peerId, String ip) async {
    final location = await _ipGeoService.queryLocation(ip);
    updateIpLocation(peerId, location);
  }
}
