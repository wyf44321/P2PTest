import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:p2p_test/utils/logger.dart';
import 'package:p2p_test/utils/validators.dart';

typedef _GeoParser = String? Function(Map<String, dynamic> data);

class _GeoApi {
  final String name;
  final String Function(String ip) buildUrl;
  final _GeoParser parse;

  const _GeoApi({
    required this.name,
    required this.buildUrl,
    required this.parse,
  });
}

class IpGeoService {
  static const String _tag = 'IpGeoService';

  static final List<_GeoApi> _apis = [
    // 1. ip-api.com — 免费，45次/分钟，仅HTTP
    _GeoApi(
      name: 'ip-api.com',
      buildUrl: (ip) =>
          'http://ip-api.com/json/$ip?lang=zh-CN&fields=status,country,regionName,city,isp',
      parse: (data) {
        if (data['status'] != 'success') return null;
        final city = _str(data['city']) ?? _str(data['regionName']);
        final isp = _str(data['isp']);
        return _join(city, isp);
      },
    ),
    // 2. ipwhois.io — 免费，10000次/月，无需密钥
    _GeoApi(
      name: 'ipwhois.io',
      buildUrl: (ip) =>
          'https://ipwhois.app/json/$ip?lang=zh-CN&objects=success,country,region,city,isp',
      parse: (data) {
        if (data['success'] == false) return null;
        final city = _str(data['city']) ?? _str(data['region']);
        final isp = _str(data['isp']);
        return _join(city, isp);
      },
    ),
    // 3. ipapi.co — 免费，1000次/天
    _GeoApi(
      name: 'ipapi.co',
      buildUrl: (ip) => 'https://ipapi.co/$ip/json/',
      parse: (data) {
        if (data.containsKey('error')) return null;
        final city = _str(data['city']) ?? _str(data['region']);
        final org = _str(data['org']);
        return _join(city, org);
      },
    ),
    // 4. freeipapi.com — 免费，60次/分钟
    _GeoApi(
      name: 'freeipapi.com',
      buildUrl: (ip) => 'https://freeipapi.com/api/json/$ip',
      parse: (data) {
        final city = _str(data['cityName']) ?? _str(data['regionName']);
        final country = _str(data['countryName']);
        return city ?? country;
      },
    ),
    // 5. realip.cc — 国内服务
    _GeoApi(
      name: 'realip.cc',
      buildUrl: (ip) => 'https://realip.cc/api/ip/$ip',
      parse: (data) {
        final city = _str(data['city']) ?? _str(data['province']);
        final isp = _str(data['isp']);
        return _join(city, isp);
      },
    ),
    // 6. ip.sb (via API) — 免费
    _GeoApi(
      name: 'ip.sb',
      buildUrl: (ip) => 'https://api.ip.sb/geoip/$ip',
      parse: (data) {
        final city = _str(data['city']) ?? _str(data['region']);
        final isp = _str(data['isp']) ?? _str(data['organization']);
        return _join(city, isp);
      },
    ),
  ];

  final Map<String, String> _cache = {};

  Future<String> queryLocation(String ip) async {
    if (_cache.containsKey(ip)) return _cache[ip]!;

    if (Validators.isPrivateIp(ip)) {
      _cache[ip] = '内网地址';
      return _cache[ip]!;
    }

    for (final api in _apis) {
      try {
        final url = api.buildUrl(ip);
        final response = await http
            .get(Uri.parse(url), headers: {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final location = api.parse(data);
          if (location != null && location.isNotEmpty) {
            _cache[ip] = location;
            AppLogger.info(_tag, 'IP $ip -> $location (via ${api.name})');
            return location;
          }
        }
        AppLogger.debug(
            _tag, '${api.name} returned no result for $ip (HTTP ${response.statusCode})');
      } catch (e) {
        AppLogger.debug(_tag, '${api.name} failed for $ip: $e');
      }
    }

    _cache[ip] = '未知';
    return '未知';
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static String? _join(String? city, String? detail) {
    if (city != null && detail != null) return '$city/$detail';
    return city ?? detail;
  }

  void clearCache() {
    _cache.clear();
  }
}
