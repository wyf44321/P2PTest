import 'package:flutter/foundation.dart';

import 'package:p2p_test/models/peer_candidate.dart';

enum ConnectionStatus {
  connecting,
  connected,
  reconnecting,
  disconnected,
  degradedMonitoring,
  failed,
}

extension ConnectionStatusDisplay on ConnectionStatus {
  String get label {
    switch (this) {
      case ConnectionStatus.connecting:
        return '连接中...';
      case ConnectionStatus.connected:
        return '已连接';
      case ConnectionStatus.reconnecting:
        return '重连中';
      case ConnectionStatus.disconnected:
        return '已断开';
      case ConnectionStatus.degradedMonitoring:
        return '已断开（每分钟探测）';
      case ConnectionStatus.failed:
        return '连接失败';
    }
  }

  String get colorName {
    switch (this) {
      case ConnectionStatus.connecting:
        return 'yellow';
      case ConnectionStatus.connected:
        return 'green';
      case ConnectionStatus.reconnecting:
        return 'orange';
      case ConnectionStatus.disconnected:
        return 'red';
      case ConnectionStatus.degradedMonitoring:
        return 'grey';
      case ConnectionStatus.failed:
        return 'red';
    }
  }
}

@immutable
class MonitoredPeer {
  final String id;
  final String ip;
  final int port;
  final List<PeerCandidate> candidates;
  final String? activeIp;
  final int? activePort;
  final String? ipLocation;
  final ConnectionStatus status;
  final int? rttMs;
  final double? packetLoss;
  final DateTime createdAt;
  final DateTime? lastConnectedAt;
  final int reconnectCount;

  const MonitoredPeer({
    required this.id,
    required this.ip,
    required this.port,
    this.candidates = const [],
    this.activeIp,
    this.activePort,
    this.ipLocation,
    this.status = ConnectionStatus.connecting,
    this.rttMs,
    this.packetLoss,
    required this.createdAt,
    this.lastConnectedAt,
    this.reconnectCount = 0,
  });

  /// The primary display address (first public or first candidate).
  String get address => '$ip:$port';

  /// The address currently used for communication.
  String get activeAddress =>
      (activeIp != null && activePort != null)
          ? '$activeIp:$activePort'
          : address;

  /// Effective IP for communication (active or fallback to primary).
  String get effectiveIp => activeIp ?? ip;

  /// Effective port for communication (active or fallback to primary).
  int get effectivePort => activePort ?? port;

  /// All candidates to try during hole punch. Falls back to primary address.
  List<PeerCandidate> get effectiveCandidates =>
      candidates.isNotEmpty
          ? candidates
          : [PeerCandidate(ip, port)];

  String get displayRtt =>
      (status == ConnectionStatus.connected && rttMs != null)
          ? '${rttMs}ms'
          : '--';

  String get displayPacketLoss =>
      (status == ConnectionStatus.connected && packetLoss != null)
          ? '${packetLoss!.toStringAsFixed(1)}%'
          : '--';

  String get displayLocation {
    if (ipLocation == null) return '查询中...';
    return ipLocation!;
  }

  String get displayStatus {
    if (status == ConnectionStatus.reconnecting && reconnectCount > 0) {
      return '重连中 ($reconnectCount/5)';
    }
    return status.label;
  }

  MonitoredPeer copyWith({
    String? id,
    String? ip,
    int? port,
    List<PeerCandidate>? candidates,
    String? activeIp,
    int? activePort,
    String? ipLocation,
    ConnectionStatus? status,
    int? rttMs,
    double? packetLoss,
    DateTime? createdAt,
    DateTime? lastConnectedAt,
    int? reconnectCount,
    bool clearRtt = false,
    bool clearPacketLoss = false,
    bool clearActive = false,
  }) {
    return MonitoredPeer(
      id: id ?? this.id,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      candidates: candidates ?? this.candidates,
      activeIp: clearActive ? null : (activeIp ?? this.activeIp),
      activePort: clearActive ? null : (activePort ?? this.activePort),
      ipLocation: ipLocation ?? this.ipLocation,
      status: status ?? this.status,
      rttMs: clearRtt ? null : (rttMs ?? this.rttMs),
      packetLoss: clearPacketLoss ? null : (packetLoss ?? this.packetLoss),
      createdAt: createdAt ?? this.createdAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      reconnectCount: reconnectCount ?? this.reconnectCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ip': ip,
      'port': port,
      'candidates': candidates.map((c) => c.toJson()).toList(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory MonitoredPeer.fromJson(Map<String, dynamic> json) {
    final candidatesList = json['candidates'] as List?;
    return MonitoredPeer(
      id: json['id'] as String,
      ip: json['ip'] as String,
      port: json['port'] as int,
      candidates: candidatesList != null
          ? candidatesList
              .map((c) => PeerCandidate.fromJson(c as Map<String, dynamic>))
              .toList()
          : [],
      createdAt: DateTime.parse(json['created_at'] as String),
      status: ConnectionStatus.connecting,
    );
  }
}
