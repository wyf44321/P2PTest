class AppConstants {
  AppConstants._();

  static const String appName = 'P2PTest';
  static const String appSubtitle = 'P2P 网络测试工具';
  static const String appVersion = 'v2.3.0';

  static const Duration stunTimeout = Duration(seconds: 5);
  static const Duration holePunchTimeout = Duration(seconds: 30);
  static const Duration holePunchInterval = Duration(milliseconds: 200);

  static const Duration probeInterval = Duration(seconds: 1);
  static const Duration degradedProbeInterval = Duration(minutes: 1);
  static const Duration packetLossCalcInterval = Duration(seconds: 5);

  static const int pingWindowSize = 30;
  static const int pongTimeoutMs = 3000;

  static const List<Duration> reconnectIntervals = [
    Duration(seconds: 1),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];
  static const int maxReconnectAttempts = 5;

  static const int maxMonitoredPeers = 20;

  /// Port prediction kicks in after this delay within a hole-punch attempt.
  static const Duration portPredictionDelay = Duration(seconds: 1);

  /// Number of delta-steps to try when the port allocation pattern is
  /// consistent (each step = observed delta, both directions).
  static const int portPredictionRangeConsistent = 20;

  /// Number of ports to try on each side when the allocation pattern is
  /// unpredictable (sequential ±1 scan + delta-based guesses).
  static const int portPredictionRangeWide = 100;
}
