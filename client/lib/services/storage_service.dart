import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:p2p_test/models/self_info.dart';
import 'package:p2p_test/utils/logger.dart';

class StorageService {
  static const String _tag = 'StorageService';
  static const String _stunConfigKey = 'stun_config';

  // --- STUN 服务器配置持久化 ---

  Future<void> saveStunConfig(StunConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_stunConfigKey, jsonEncode(config.toJson()));
      AppLogger.debug(_tag, 'Saved STUN config: ${config.selectedServer}');
    } catch (e) {
      AppLogger.error(_tag, 'Failed to save STUN config', e);
    }
  }

  Future<StunConfig?> loadStunConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_stunConfigKey);
      if (jsonStr == null) return null;
      final config =
          StunConfig.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
      AppLogger.info(
          _tag, 'Loaded STUN config: ${config.selectedServer}');
      return config;
    } catch (e) {
      AppLogger.error(_tag, 'Failed to load STUN config', e);
      return null;
    }
  }
}
