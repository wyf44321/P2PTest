class AppConstants {
  AppConstants._();

  static const String appName = 'P2PTest';
  static const String appSubtitle = 'P2P 网络测试工具';
  static const String appVersion = 'v3.1.0';

  // STUN
  static const Duration stunTimeout = Duration(seconds: 5);

  // Keepalive: send STUN packet if socket idle for this duration
  static const Duration keepaliveTimeout = Duration(seconds: 5);

  // Per-peer sending interval
  static const Duration peerSendInterval = Duration(milliseconds: 10);

  // No reply for this long → timeout (reconnect or disconnect)
  static const Duration peerReplyTimeout = Duration(minutes: 1);

  // Maximum reconnect attempts before marking disconnected
  static const int maxReconnectAttempts = 5;

  // Symmetric NAT port prediction: time-compensated dual-zone scanning
  static const int symmetricBatchSize = 32;

  // Hot zone: tight window around estimated center, scanned with 2/3 of batch.
  // Measured in step-multiples (actual port range = hotRadius * portStep).
  static const int symmetricHotRadius = 64;

  // Extended zone: adaptive wider window, scanned with 1/3 of batch.
  // Measured in step-multiples.
  static const int symmetricMinExtRadius = 128;
  static const int symmetricMaxExtRadius = 2048;

  // Fallback range when no velocity data (old metadata format)
  static const int symmetricFallbackRange = 256;

  // Adaptive widening: after this many send cycles without connection,
  // start expanding the scan range. Each subsequent cycle multiplies
  // hot/ext radii by (1 + cyclesOver / wideningDivisor).
  static const int symmetricWideningStartCycle = 200;
  static const double symmetricWideningDivisor = 500.0;
  static const double symmetricMaxWidening = 4.0;

  // Birthday attack: auxiliary sockets opened per symmetric NAT peer.
  // Each socket targets one predicted port, giving the peer K× more
  // stable NAT mappings to hit. Only used when peer is symmetric.
  static const int birthdaySocketCount = 16;
  // For SYM↔SYM: double the sockets since it's the hardest scenario
  static const int birthdaySocketCountSymSym = 32;
  // Interval to reshuffle birthday target ports if no connection yet
  static const Duration birthdayReshuffleInterval = Duration(seconds: 8);
  // Birthday sockets send keepalive at this interval to maintain NAT mappings
  static const Duration birthdaySendInterval = Duration(milliseconds: 100);
  // Birthday target range multiplier for SYM↔SYM (wider coverage)
  static const int birthdayRangeMin = 128;
  static const int birthdayRangeMax = 1024;

  // How long to try private (LAN) candidates before falling back to public
  static const Duration privatePhaseDuration = Duration(seconds: 3);

  // Ping/pong interval for latency & loss measurement (after connection)
  static const Duration pingInterval = Duration(milliseconds: 500);

  static const int maxMonitoredPeers = 20;
}
