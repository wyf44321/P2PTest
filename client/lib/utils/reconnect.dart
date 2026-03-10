import 'dart:async';

import 'package:p2p_test/config/constants.dart';

class ReconnectController {
  int _attempt = 0;
  Timer? _timer;
  bool _isReconnecting = false;

  final Future<bool> Function() onReconnect;
  final void Function() onSuccess;
  final void Function() onFailure;
  final void Function(int attempt, int maxAttempts) onAttemptUpdate;

  ReconnectController({
    required this.onReconnect,
    required this.onSuccess,
    required this.onFailure,
    required this.onAttemptUpdate,
  });

  bool get isReconnecting => _isReconnecting;
  int get currentAttempt => _attempt;

  void start() {
    if (_isReconnecting) return;
    _isReconnecting = true;
    _attempt = 0;
    _scheduleNext();
  }

  void _scheduleNext() {
    if (_attempt >= AppConstants.maxReconnectAttempts) {
      _isReconnecting = false;
      onFailure();
      return;
    }
    final delay = AppConstants.reconnectIntervals[_attempt];
    _timer = Timer(delay, () async {
      _attempt++;
      onAttemptUpdate(_attempt, AppConstants.maxReconnectAttempts);
      final success = await onReconnect();
      if (success) {
        _isReconnecting = false;
        onSuccess();
      } else {
        _scheduleNext();
      }
    });
  }

  void cancel() {
    _timer?.cancel();
    _isReconnecting = false;
    _attempt = 0;
  }

  void dispose() {
    cancel();
  }
}
