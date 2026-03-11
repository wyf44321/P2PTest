class AppConstants {
  AppConstants._();

  static const String appName = 'P2PTest';
  static const String appSubtitle = 'P2P 网络测试工具';
  static const String appVersion = 'v3.0.0';

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

  // Hot zone: tight window around estimated center, scanned with 2/3 of batch
  static const int symmetricHotRadius = 64;

  // Extended zone: adaptive wider window, scanned with 1/3 of batch
  static const int symmetricMinExtRadius = 128;
  static const int symmetricMaxExtRadius = 2048;

  // Fallback range when no velocity data (old metadata format)
  static const int symmetricFallbackRange = 256;

  // How long to try private (LAN) candidates before falling back to public
  static const Duration privatePhaseDuration = Duration(seconds: 3);

  // Ping/pong interval for latency & loss measurement (after connection)
  static const Duration pingInterval = Duration(milliseconds: 500);

  static const int maxMonitoredPeers = 20;
}
