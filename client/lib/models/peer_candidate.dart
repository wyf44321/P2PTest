import 'package:flutter/foundation.dart';

@immutable
class PeerCandidate {
  final String ip;
  final int port;

  const PeerCandidate(this.ip, this.port);

  bool get isIPv6 => ip.contains(':');

  String get address => isIPv6 ? '[$ip]:$port' : '$ip:$port';

  Map<String, dynamic> toJson() => {'ip': ip, 'port': port};

  factory PeerCandidate.fromJson(Map<String, dynamic> json) =>
      PeerCandidate(json['ip'] as String, json['port'] as int);

  @override
  bool operator ==(Object other) =>
      other is PeerCandidate && other.ip == ip && other.port == port;

  @override
  int get hashCode => Object.hash(ip, port);

  @override
  String toString() => address;
}
