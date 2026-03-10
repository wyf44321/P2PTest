import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:p2p_test/utils/logger.dart';
import 'package:p2p_test/utils/validators.dart';

class IpGeoService {
  static const String _tag = 'IpGeoService';
  static const String _apiBase = 'http://ip-api.com/json';

  final Map<String, String> _cache = {};

  Future<String> queryLocation(String ip) async {
    if (_cache.containsKey(ip)) return _cache[ip]!;

    if (Validators.isPrivateIp(ip)) {
      _cache[ip] = '内网地址';
      return _cache[ip]!;
    }

    try {
      final response = await http
          .get(
            Uri.parse(
                '$_apiBase/$ip?lang=zh-CN&fields=status,country,regionName,city,isp'),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          final city = data['city'] ?? data['regionName'] ?? '';
          final isp = data['isp'] ?? '';
          final location =
              city.toString().isNotEmpty ? '$city/$isp' : isp.toString();
          _cache[ip] = location.isNotEmpty ? location : '未知';
          AppLogger.info(_tag, 'IP $ip -> ${_cache[ip]}');
          return _cache[ip]!;
        }
      }

      _cache[ip] = '未知';
      return '未知';
    } catch (e) {
      AppLogger.error(_tag, 'Failed to query location for $ip', e);
      return '未知';
    }
  }

  void clearCache() {
    _cache.clear();
  }
}
