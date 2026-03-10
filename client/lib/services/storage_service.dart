import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:p2p_test/models/monitored_peer.dart';
import 'package:p2p_test/models/self_info.dart';
import 'package:p2p_test/utils/logger.dart';

class StorageService {
  static const String _tag = 'StorageService';
  static const String _peersKey = 'monitored_peers';
  static const String _stunConfigKey = 'stun_config';

  // --- 监听用户持久化 ---

  Future<void> savePeers(List<MonitoredPeer> peers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = peers.map((p) => p.toJson()).toList();
      await prefs.setString(_peersKey, jsonEncode(data));
      AppLogger.debug(_tag, 'Saved ${peers.length} peers');
    } catch (e) {
      AppLogger.error(_tag, 'Failed to save peers', e);
    }
  }

  Future<List<MonitoredPeer>> loadPeers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_peersKey);
      if (jsonStr == null) return [];
      final list = jsonDecode(jsonStr) as List;
      final peers =
          list.map((j) => MonitoredPeer.fromJson(j as Map<String, dynamic>)).toList();
      AppLogger.info(_tag, 'Loaded ${peers.length} peers');
      return peers;
    } catch (e) {
      AppLogger.error(_tag, 'Failed to load peers', e);
      return [];
    }
  }

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
