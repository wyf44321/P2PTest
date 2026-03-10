import 'package:flutter/foundation.dart';

import 'package:p2p_test/models/monitored_peer.dart';
import 'package:p2p_test/models/peer_candidate.dart';
import 'package:p2p_test/services/ip_geo_service.dart';
import 'package:p2p_test/services/monitor_service.dart';
import 'package:p2p_test/services/storage_service.dart';
import 'package:p2p_test/services/udp_service.dart';
import 'package:p2p_test/utils/logger.dart';
import 'package:p2p_test/utils/validators.dart';

class PeerProvider extends ChangeNotifier {
  static const String _tag = 'PeerProvider';

  final UdpService _udpService;
  final StorageService _storageService;
  final MonitorService _monitorService;
  final IpGeoService _ipGeoService;

  List<MonitoredPeer> _peers = [];

  PeerProvider({
    required UdpService udpService,
    required StorageService storageService,
    required MonitorService monitorService,
    required IpGeoService ipGeoService,
  })  : _udpService = udpService,
        _storageService = storageService,
        _monitorService = monitorService,
        _ipGeoService = ipGeoService {
    _setupMonitorCallbacks();
  }

  List<MonitoredPeer> get peers => List.unmodifiable(_peers);

  bool get hasDisconnectedPeers => _peers.any(
        (p) =>
            p.status == ConnectionStatus.disconnected ||
            p.status == ConnectionStatus.degradedMonitoring ||
            p.status == ConnectionStatus.failed,
      );

  List<MonitoredPeer> get connectedPeers =>
      _peers.where((p) => p.status == ConnectionStatus.connected).toList();

  void _setupMonitorCallbacks() {
    _monitorService.getConnectedPeers = () => connectedPeers;
    _monitorService.getAllPeers = () => _peers;
    _monitorService.getPeer = (id) {
      try {
        return _peers.firstWhere((p) => p.id == id);
      } catch (_) {
        return null;
      }
    };
    _monitorService.updatePeerStatus = updatePeerStatus;
    _monitorService.updateRtt = updateRTT;
    _monitorService.updatePacketLoss = updatePacketLoss;
    _monitorService.updateReconnectProgress = updateReconnectProgress;
    _monitorService.updateActiveAddress = updateActiveAddress;
  }

  Future<void> loadSavedPeers() async {
    final saved = await _storageService.loadPeers();
    _peers = saved;
    notifyListeners();

    for (final peer in _peers) {
      _queryIpLocation(peer.id, peer.ip);
      _connectPeer(peer);
    }
  }

  /// Add a peer with a list of candidate addresses.
  Future<void> addPeer(List<PeerCandidate> candidates) async {
    if (candidates.isEmpty) return;

    // Use the first public IP as primary, or fall back to first candidate.
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
    );

    _peers = [..._peers, peer];
    notifyListeners();
    await _savePeers();

    _queryIpLocation(id, primary.ip);
    _connectPeer(peer);
  }

  Future<void> removePeer(String peerId) async {
    final peer = _findPeer(peerId);
    if (peer == null) return;

    _monitorService.stopMonitoring(peerId);
    _udpService.markDisconnected(peer.effectiveIp, peer.effectivePort);

    _peers = _peers.where((p) => p.id != peerId).toList();
    notifyListeners();
    await _savePeers();

    AppLogger.info(_tag, 'Removed peer $peerId');
  }

  Future<void> clearDisconnectedPeers() async {
    final toRemove = _peers
        .where((p) =>
            p.status == ConnectionStatus.disconnected ||
            p.status == ConnectionStatus.degradedMonitoring ||
            p.status == ConnectionStatus.failed)
        .map((p) => p.id)
        .toList();

    if (toRemove.isEmpty) return;

    _monitorService.clearDisconnectedPeers(toRemove);

    for (final peerId in toRemove) {
      final peer = _findPeer(peerId);
      if (peer != null) {
        _udpService.markDisconnected(peer.effectiveIp, peer.effectivePort);
      }
    }

    _peers = _peers
        .where((p) =>
            p.status != ConnectionStatus.disconnected &&
            p.status != ConnectionStatus.degradedMonitoring &&
            p.status != ConnectionStatus.failed)
        .toList();
    notifyListeners();
    await _savePeers();

    AppLogger.info(_tag, 'Cleared ${toRemove.length} disconnected peers');
  }

  void updatePeerStatus(String peerId, ConnectionStatus status) {
    _updatePeer(peerId, (p) {
      if (status == ConnectionStatus.connected) {
        return p.copyWith(
          status: status,
          lastConnectedAt: DateTime.now(),
          reconnectCount: 0,
        );
      }
      if (status == ConnectionStatus.disconnected ||
          status == ConnectionStatus.degradedMonitoring) {
        return p.copyWith(status: status, clearRtt: true, clearPacketLoss: true);
      }
      return p.copyWith(status: status);
    });
  }

  void updateRTT(String peerId, int rtt) {
    _updatePeer(peerId, (p) => p.copyWith(rttMs: rtt));
  }

  void updatePacketLoss(String peerId, double packetLoss) {
    _updatePeer(peerId, (p) => p.copyWith(packetLoss: packetLoss));
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

  bool peerExists(List<PeerCandidate> candidates) {
    final newAddrs = candidates.map((c) => c.address).toSet();
    return _peers.any((p) {
      final existingAddrs = p.effectiveCandidates.map((c) => c.address).toSet();
      return existingAddrs.intersection(newAddrs).isNotEmpty;
    });
  }

  // --- Private helpers ---

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

  Future<void> _savePeers() async {
    await _storageService.savePeers(_peers);
  }

  Future<void> _queryIpLocation(String peerId, String ip) async {
    final location = await _ipGeoService.queryLocation(ip);
    updateIpLocation(peerId, location);
  }

  Future<void> _connectPeer(MonitoredPeer peer) async {
    try {
      final candidates = peer.effectiveCandidates;
      final result = await _udpService.holePunchMultiCandidate(candidates);
      if (result != null) {
        updateActiveAddress(peer.id, result.ip, result.port);
        updatePeerStatus(peer.id, ConnectionStatus.connected);
        _monitorService.startMonitoring(peer.id);
      } else {
        AppLogger.warning(
            _tag, 'Initial punch timeout for ${peer.address}, scheduling reconnect');
        updatePeerStatus(peer.id, ConnectionStatus.reconnecting);
        _monitorService.scheduleReconnect(peer.id, candidates);
      }
    } catch (e) {
      AppLogger.error(_tag, 'Connection failed for ${peer.address}', e);
      updatePeerStatus(peer.id, ConnectionStatus.reconnecting);
      _monitorService.scheduleReconnect(
          peer.id, peer.effectiveCandidates);
    }
  }
}
