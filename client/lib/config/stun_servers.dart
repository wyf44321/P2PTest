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
      StunServerOption('Cloudflare', 'stun.cloudflare.com', 3478);

  static const List<StunServerOption> defaultServers = [
    StunServerOption('Cloudflare', 'stun.cloudflare.com', 3478),
    StunServerOption('Google STUN', 'stun.l.google.com', 19302),
    StunServerOption('Google STUN 1', 'stun1.l.google.com', 19302),
    StunServerOption('Google STUN 2', 'stun2.l.google.com', 19302),
    StunServerOption('Nextcloud', 'stun.nextcloud.com', 443),
    StunServerOption('VoIPBuster', 'stun.voipbuster.com', 3478),
  ];
}
