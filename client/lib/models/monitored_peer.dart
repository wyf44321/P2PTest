import 'package:flutter/foundation.dart';

import 'package:p2p_test/models/peer_candidate.dart';

enum ConnectionStatus {
  connecting,
  connected,
  reconnecting,
  disconnected,
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
  final DateTime createdAt;
  final DateTime? lastConnectedAt;
  final int reconnectCount;
  final String? natMetadata;
  final double? latencyMs;
  final double? packetLossPercent;

  const MonitoredPeer({
    required this.id,
    required this.ip,
    required this.port,
    this.candidates = const [],
    this.activeIp,
    this.activePort,
    this.ipLocation,
    this.status = ConnectionStatus.connecting,
    required this.createdAt,
    this.lastConnectedAt,
    this.reconnectCount = 0,
    this.natMetadata,
    this.latencyMs,
    this.packetLossPercent,
  });

  String get address => '$ip:$port';

  String get activeAddress =>
      (activeIp != null && activePort != null)
          ? '$activeIp:$activePort'
          : address;

  String get effectiveIp => activeIp ?? ip;

  int get effectivePort => activePort ?? port;

  List<PeerCandidate> get effectiveCandidates =>
      candidates.isNotEmpty
          ? candidates
          : [PeerCandidate(ip, port)];

  bool get isSymmetricNat =>
      natMetadata != null && natMetadata!.startsWith('sym');

  int? get symmetricPortStep {
    if (natMetadata == null) return null;
    final match = RegExp(r'd=(\d+)').firstMatch(natMetadata!);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  int? get symmetricPortVelocity {
    if (natMetadata == null) return null;
    final match = RegExp(r'v=(\d+)').firstMatch(natMetadata!);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  int? get symmetricProbeTimestamp {
    if (natMetadata == null) return null;
    final match = RegExp(r't=(\d+)').firstMatch(natMetadata!);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

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

  String get latencyDisplay {
    if (latencyMs == null) return '-';
    return '${latencyMs!.round()}ms';
  }

  String get lossDisplay {
    if (packetLossPercent == null) return '-';
    return '${packetLossPercent!.toStringAsFixed(1)}%';
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
    DateTime? createdAt,
    DateTime? lastConnectedAt,
    int? reconnectCount,
    String? natMetadata,
    double? latencyMs,
    double? packetLossPercent,
    bool clearActive = false,
    bool clearStats = false,
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
      createdAt: createdAt ?? this.createdAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      reconnectCount: reconnectCount ?? this.reconnectCount,
      natMetadata: natMetadata ?? this.natMetadata,
      latencyMs: clearStats ? null : (latencyMs ?? this.latencyMs),
      packetLossPercent: clearStats
          ? null
          : (packetLossPercent ?? this.packetLossPercent),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ip': ip,
      'port': port,
      'candidates': candidates.map((c) => c.toJson()).toList(),
      'created_at': createdAt.toIso8601String(),
      'nat_metadata': natMetadata,
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
      natMetadata: json['nat_metadata'] as String?,
    );
  }
}
