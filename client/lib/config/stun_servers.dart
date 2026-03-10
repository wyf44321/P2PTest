class StunServerOption {
  final String name;
  final String host;
  final int port;

  const StunServerOption(this.name, this.host, this.port);

  String get address => '$host:$port';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StunServerOption && host == other.host && port == other.port;

  @override
  int get hashCode => host.hashCode ^ port.hashCode;
}

class StunServers {
  StunServers._();

  static const StunServerOption initialDefault =
      StunServerOption('自建 STUN 1', '61.151.231.231', 2311);

  static const List<StunServerOption> defaultServers = [
    StunServerOption('自建 STUN 1', '61.151.231.231', 2311),
    StunServerOption('自建 STUN 2', '61.151.231.231', 2312),
    StunServerOption('Google STUN', 'stun.l.google.com', 19302),
    StunServerOption('Google STUN 1', 'stun1.l.google.com', 19302),
    StunServerOption('Google STUN 2', 'stun2.l.google.com', 19302),
    StunServerOption('Cloudflare', 'stun.cloudflare.com', 3478),
    StunServerOption('Nextcloud', 'stun.nextcloud.com', 443),
    StunServerOption('stunprotocol.org', 'stun.stunprotocol.org', 3478),
    StunServerOption('Ekiga', 'stun.ekiga.net', 3478),
    StunServerOption('IdeasIP', 'stun.ideasip.com', 3478),
    StunServerOption('Schlund', 'stun.schlund.de', 3478),
  ];
}
