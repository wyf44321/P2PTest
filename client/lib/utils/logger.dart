import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error }

class AppLogger {
  static LogLevel _level = kDebugMode ? LogLevel.debug : LogLevel.warning;

  AppLogger._();

  static void init() {
    _level = kDebugMode ? LogLevel.debug : LogLevel.warning;
  }

  static void setLevel(LogLevel level) {
    _level = level;
  }

  static void debug(String tag, String message) {
    if (_level.index <= LogLevel.debug.index) {
      _log('DEBUG', tag, message);
    }
  }

  static void info(String tag, String message) {
    if (_level.index <= LogLevel.info.index) {
      _log('INFO', tag, message);
    }
  }

  static void warning(String tag, String message) {
    if (_level.index <= LogLevel.warning.index) {
      _log('WARN', tag, message);
    }
  }

  static void error(String tag, String message, [Object? error]) {
    if (_level.index <= LogLevel.error.index) {
      _log('ERROR', tag, '$message${error != null ? ' | $error' : ''}');
    }
  }

  static void _log(String level, String tag, String message) {
    final timestamp = DateTime.now().toIso8601String();
    print('[$timestamp][$level][$tag] $message');
  }
}
