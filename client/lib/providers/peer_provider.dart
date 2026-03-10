import 'package:flutter/foundation.dart';

import 'package:p2p_test/models/monitored_peer.dart';
import 'package:p2p_test/models/peer_candidate.dart';
import 'package:p2p_test/models/self_info.dart';
import 'package:p2p_test/providers/self_info_provider.dart';
import 'package:p2p_test/services/ip_geo_service.dart';
import 'package:p2p_test/services/monitor_service.dart';
import 'package:p2p_test/services/udp_service.dart';
import 'package:p2p_test/utils/logger.dart';
import 'package:p2p_test/utils/validators.dart' show ParsedCandidateInput, Validators;

class PeerProvider extends ChangeNotifier {
  static const String _tag = 'PeerProvider';

  final UdpService _udpService;
  final MonitorService _monitorService;
  final IpGeoService _ipGeoService;

  List<MonitoredPeer> _peers = [];

  PeerProvider({
    required UdpService udpService,
    required MonitorService monitorService,
    required IpGeoService ipGeoService,
    required SelfInfoProvider selfInfoProvider,
  })  : _udpService = udpService,
        _monitorService = monitorService,
        _ipGeoService = ipGeoService {
    _setupMonitorCallbacks();
    _udpService.onIncomingPeerConnected = _onIncomingPeerConnected;
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

  /// Add a peer from parsed candidate input (addresses + optional NAT metadata).
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
      peerNatType: input.peerNatType,
      peerPortDelta: input.peerPortDelta,
      peerIsConsistentDelta: input.peerIsConsistentDelta,
    );

    _peers = [..._peers, peer];
    notifyListeners();

    _queryIpLocation(id, primary.ip);
    _connectPeer(peer);
  }

  void removePeer(String peerId) {
    final peer = _findPeer(peerId);
    if (peer == null) return;

    _monitorService.stopMonitoring(peerId);
    _udpService.markDisconnected(peer.effectiveIp, peer.effectivePort);

    _peers = _peers.where((p) => p.id != peerId).toList();
    notifyListeners();

    AppLogger.info(_tag, 'Removed peer $peerId');
  }

  void clearDisconnectedPeers() {
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

  bool peerExists(ParsedCandidateInput input) {
    final newAddrs = input.candidates.map((c) => c.address).toSet();
    return _peers.any((p) {
      final existingAddrs = p.effectiveCandidates.map((c) => c.address).toSet();
      return existingAddrs.intersection(newAddrs).isNotEmpty;
    });
  }

  // --- Private helpers ---

  void _onIncomingPeerConnected(String ip, int port) {
    final addr = '$ip:$port';

    // Match by full address, candidate addresses, or source port.
    // Same source port from different IPs means the same client sending
    // via different network interfaces.
    MonitoredPeer? existing;
    for (final p in _peers) {
      if (p.activeAddress == addr ||
          p.address == addr ||
          p.effectiveCandidates.any((c) => c.address == addr) ||
          p.effectivePort == port) {
        existing = p;
        break;
      }
    }

    if (existing != null) {
      if (existing.status != ConnectionStatus.connected) {
        _monitorService.stopMonitoring(existing.id);
        updateActiveAddress(existing.id, ip, port);
        updatePeerStatus(existing.id, ConnectionStatus.connected);
        _monitorService.startMonitoring(existing.id);
        AppLogger.info(
            _tag, 'Reconnected existing peer ${existing.id} via incoming punch from $addr');
      } else {
        AppLogger.debug(
            _tag, 'Ignored duplicate incoming punch from $addr (same client as ${existing.id})');
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
    _monitorService.startMonitoring(id);

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

  Future<void> _connectPeer(MonitoredPeer peer) async {
    final usePrediction = peer.usePeerPortPrediction;
    try {
      final candidates = peer.effectiveCandidates;
      final result = await _udpService.holePunchMultiCandidate(
        candidates,
        enablePortPrediction: usePrediction,
        portDelta: peer.peerPortDelta,
        isConsistentDelta: peer.peerIsConsistentDelta,
      );
      if (result != null) {
        updateActiveAddress(peer.id, result.ip, result.port);
        updatePeerStatus(peer.id, ConnectionStatus.connected);
        _monitorService.startMonitoring(peer.id);
      } else {
        AppLogger.warning(
            _tag, 'Initial punch timeout for ${peer.address}, scheduling reconnect');
        updatePeerStatus(peer.id, ConnectionStatus.reconnecting);
        _monitorService.scheduleReconnect(peer.id, candidates,
            enablePortPrediction: usePrediction,
            portDelta: peer.peerPortDelta,
            isConsistentDelta: peer.peerIsConsistentDelta);
      }
    } catch (e) {
      AppLogger.error(_tag, 'Connection failed for ${peer.address}', e);
      updatePeerStatus(peer.id, ConnectionStatus.reconnecting);
      _monitorService.scheduleReconnect(
          peer.id, peer.effectiveCandidates,
          enablePortPrediction: usePrediction,
          portDelta: peer.peerPortDelta,
          isConsistentDelta: peer.peerIsConsistentDelta);
    }
  }
}
