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
      StunServerOption('Google STUN 4', 'stun4.l.google.com', 19302);

  static const List<StunServerOption> defaultServers = [
    StunServerOption('Google STUN 4', 'stun4.l.google.com', 19302),
    StunServerOption('Cloudflare', 'stun.cloudflare.com', 3478),
    StunServerOption('Sonetel', 'stun.sonetel.net', 3478),
    StunServerOption('AEBC VoIP', 'stun.voip.aebc.com', 3478),
    StunServerOption('Ippi', 'stun.ippi.fr', 3478),
    StunServerOption('FreeSWITCH', 'stun.freeswitch.org', 3478),
    StunServerOption('MyWatson', 'stun.mywatson.it', 3478),
    StunServerOption('USFamily', 'stun.usfamily.net', 3478),
    StunServerOption('Nextcloud', 'stun.nextcloud.com', 443),
    StunServerOption('VozTele', 'stun.voztele.com', 3478),
  ];
}
