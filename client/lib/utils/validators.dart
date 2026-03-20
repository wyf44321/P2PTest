import 'dart:io';

import 'package:p2p_test/models/peer_candidate.dart';

/// Parsed result of a candidate string, optionally with NAT metadata.
class ParsedCandidateInput {
  final List<PeerCandidate> candidates;
  final String? natMetadata;

  const ParsedCandidateInput({
    required this.candidates,
    this.natMetadata,
  });
}

class Validators {
  Validators._();

  static final _ipv4Pattern = RegExp(
    r'^((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$',
  );

  static bool isIPv4(String ip) => _ipv4Pattern.hasMatch(ip);

  static bool isIPv6(String ip) {
    if (!ip.contains(':')) return false;
    final addr = InternetAddress.tryParse(ip);
    return addr != null && addr.type == InternetAddressType.IPv6;
  }

  static bool isValidIp(String ip) => isIPv4(ip) || isIPv6(ip);

  /// Whether an IPv6 address has global scope (routable on the internet).
  static bool isGlobalIPv6(String ip) {
    final addr = InternetAddress.tryParse(ip);
    if (addr == null || addr.type != InternetAddressType.IPv6) return false;
    if (addr.isLoopback || addr.isLinkLocal) return false;
    final lower = ip.toLowerCase();
    // ULA (fc00::/7)
    if (lower.startsWith('fc') || lower.startsWith('fd')) return false;
    // IPv4-mapped (::ffff:x.x.x.x) or IPv4-compatible (::x.x.x.x)
    if (lower.startsWith('::ffff:') || lower.startsWith('::') && lower.contains('.')) {
      return false;
    }
    return true;
  }

  /// Format an IP:port pair, using [IPv6]:port notation for IPv6.
  static String formatAddress(String ip, int port) {
    if (ip.contains(':')) return '[$ip]:$port';
    return '$ip:$port';
  }

  static String? validateIp(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入 IP 地址';
    }
    if (!isValidIp(value.trim())) {
      return '请输入合法的 IPv4 或 IPv6 地址';
    }
    return null;
  }

  static String? validatePort(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入端口号';
    }
    final port = int.tryParse(value.trim());
    if (port == null || port < 1 || port > 65535) {
      return '端口号须为 1-65535';
    }
    return null;
  }

  static String? validateStunAddress(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入服务器地址';
    }
    return null;
  }

  static String? validateStunPort(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入端口号';
    }
    final port = int.tryParse(value.trim());
    if (port == null || port < 1 || port > 65535) {
      return '端口号须为 1-65535';
    }
    return null;
  }

  /// Parse "ip:port" (IPv4) or "[IPv6]:port" notation.
  static ({String ip, int port})? parseIpPort(String value) {
    final trimmed = value.trim();

    // Handle [IPv6]:port
    if (trimmed.startsWith('[')) {
      final closeBracket = trimmed.indexOf(']');
      if (closeBracket < 0) return null;
      final ip = trimmed.substring(1, closeBracket);
      if (!isIPv6(ip)) return null;
      if (closeBracket + 1 >= trimmed.length ||
          trimmed[closeBracket + 1] != ':') {
        return null;
      }
      final portStr = trimmed.substring(closeBracket + 2);
      final port = int.tryParse(portStr);
      if (port == null || port < 1 || port > 65535) return null;
      return (ip: ip, port: port);
    }

    // Handle IPv4:port
    final colonIndex = trimmed.lastIndexOf(':');
    if (colonIndex < 0) return null;
    final ip = trimmed.substring(0, colonIndex);
    final portStr = trimmed.substring(colonIndex + 1);
    if (!_ipv4Pattern.hasMatch(ip)) return null;
    final port = int.tryParse(portStr);
    if (port == null || port < 1 || port > 65535) return null;
    return (ip: ip, port: port);
  }

  static bool isPrivateIp(String ip) {
    // IPv6 private/local ranges
    if (ip.contains(':')) {
      final addr = InternetAddress.tryParse(ip);
      if (addr == null) return false;
      if (addr.isLoopback || addr.isLinkLocal) return true;
      final lower = ip.toLowerCase();
      // ULA (fc00::/7)
      if (lower.startsWith('fc') || lower.startsWith('fd')) return true;
      return false;
    }

    // IPv4 private ranges
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final nums = parts.map(int.tryParse).toList();
    if (nums.any((n) => n == null)) return false;
    final a = nums[0]!;
    final b = nums[1]!;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    if (a == 127) return true;
    return false;
  }

  /// Parse the address portion (before "|") into a list of PeerCandidate.
  static List<PeerCandidate>? parseCandidates(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final segments = _splitCandidateSegments(trimmed);
    final candidates = <PeerCandidate>[];

    for (final seg in segments) {
      final parsed = parseIpPort(seg.trim());
      if (parsed == null) return null;
      candidates.add(PeerCandidate(parsed.ip, parsed.port));
    }

    return candidates.isEmpty ? null : candidates;
  }

  /// Split candidate string by commas, respecting [IPv6] brackets.
  static List<String> _splitCandidateSegments(String value) {
    final segments = <String>[];
    int start = 0;
    bool inBracket = false;
    for (int i = 0; i < value.length; i++) {
      if (value[i] == '[') {
        inBracket = true;
      } else if (value[i] == ']') {
        inBracket = false;
      } else if (value[i] == ',' && !inBracket) {
        segments.add(value.substring(start, i));
        start = i + 1;
      }
    }
    if (start < value.length) {
      segments.add(value.substring(start));
    }
    return segments;
  }

  /// Parse a candidate string that may contain NAT metadata after "|".
  /// Format: "ip:port,[IPv6]:port|natMetadata"
  static ParsedCandidateInput? parseCandidateInput(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    String addrPart = trimmed;
    String? natMeta;

    final pipeIdx = trimmed.indexOf('|');
    if (pipeIdx >= 0) {
      addrPart = trimmed.substring(0, pipeIdx).trim();
      natMeta = trimmed.substring(pipeIdx + 1).trim();
      if (natMeta.isEmpty) natMeta = null;
    }

    final candidates = parseCandidates(addrPart);
    if (candidates == null) return null;
    return ParsedCandidateInput(
      candidates: candidates,
      natMetadata: natMeta,
    );
  }

  /// Validate a candidate string for form fields.
  static String? validateCandidateString(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入对方地址';
    }
    final input = parseCandidateInput(value);
    if (input == null) {
      return '格式错误，示例: 1.2.3.4:50001 或 [2001:db8::1]:50001';
    }
    return null;
  }
}
