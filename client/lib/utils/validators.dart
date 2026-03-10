import 'package:p2p_test/models/peer_candidate.dart';
import 'package:p2p_test/models/self_info.dart';

/// Parsed result of a candidate string that may include NAT metadata.
class ParsedCandidateInput {
  final List<PeerCandidate> candidates;
  final NatType peerNatType;
  final int? peerPortDelta;
  final bool peerIsConsistentDelta;

  const ParsedCandidateInput({
    required this.candidates,
    this.peerNatType = NatType.unknown,
    this.peerPortDelta,
    this.peerIsConsistentDelta = false,
  });
}

class Validators {
  Validators._();

  static final _ipv4Pattern = RegExp(
    r'^((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$',
  );

  static String? validateIp(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入 IP 地址';
    }
    if (!_ipv4Pattern.hasMatch(value.trim())) {
      return '请输入合法的 IP 地址';
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

  static ({String ip, int port})? parseIpPort(String value) {
    final trimmed = value.trim();
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

  /// Split raw input into the address part and optional metadata part.
  static (String addrs, String? meta) _splitMeta(String value) {
    final pipeIdx = value.indexOf('|');
    if (pipeIdx < 0) return (value, null);
    return (value.substring(0, pipeIdx), value.substring(pipeIdx + 1));
  }

  /// Parse a candidate string like "192.168.1.100:12345,1.2.3.4:50001"
  /// or "192.168.1.100:12345,1.2.3.4:50001|sym,d=2,c=1"
  /// into a list of PeerCandidate. Returns null if the string is invalid.
  static List<PeerCandidate>? parseCandidates(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final (addrPart, _) = _splitMeta(trimmed);
    final segments = addrPart.split(',');
    final candidates = <PeerCandidate>[];

    for (final seg in segments) {
      final parsed = parseIpPort(seg.trim());
      if (parsed == null) return null;
      candidates.add(PeerCandidate(parsed.ip, parsed.port));
    }

    return candidates.isEmpty ? null : candidates;
  }

  /// Parse a candidate string with optional NAT metadata.
  /// Returns null if the address part is invalid.
  static ParsedCandidateInput? parseCandidateInput(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final (addrPart, metaPart) = _splitMeta(trimmed);
    final candidates = <PeerCandidate>[];

    for (final seg in addrPart.split(',')) {
      final parsed = parseIpPort(seg.trim());
      if (parsed == null) return null;
      candidates.add(PeerCandidate(parsed.ip, parsed.port));
    }
    if (candidates.isEmpty) return null;

    var natType = NatType.unknown;
    int? portDelta;
    bool isConsistent = false;

    if (metaPart != null && metaPart.isNotEmpty) {
      final tokens = metaPart.split(',');
      for (final token in tokens) {
        final t = token.trim();
        if (t == 'sym') {
          natType = NatType.symmetric;
        } else if (t == 'cone') {
          natType = NatType.cone;
        } else if (t.startsWith('d=')) {
          portDelta = int.tryParse(t.substring(2));
        } else if (t.startsWith('c=')) {
          isConsistent = t.substring(2) == '1';
        }
      }
    }

    return ParsedCandidateInput(
      candidates: candidates,
      peerNatType: natType,
      peerPortDelta: portDelta,
      peerIsConsistentDelta: isConsistent,
    );
  }

  /// Validate a candidate string for form fields.
  static String? validateCandidateString(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入对方地址';
    }
    final candidates = parseCandidates(value);
    if (candidates == null) {
      return '地址格式错误，示例: 192.168.1.1:12345 或 192.168.1.1:12345,1.2.3.4:50001';
    }
    return null;
  }
}
