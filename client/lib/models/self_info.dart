enum StunStatus {
  loading,
  success,
  failed,
}

class StunConfig {
  final String? selectedServer;
  final bool isCustom;
  final DateTime? updatedAt;

  const StunConfig({
    this.selectedServer,
    this.isCustom = false,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'selected_server': selectedServer,
      'is_custom': isCustom,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory StunConfig.fromJson(Map<String, dynamic> json) {
    return StunConfig(
      selectedServer: json['selected_server'] as String?,
      isCustom: json['is_custom'] as bool? ?? false,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }
}

class SelfInfo {
  final String? publicIp;
  final int? publicPort;
  final String? publicIp6;
  final int? publicPort6;
  final String? localIp;
  final int? localPort;
  final int? localPort6;
  final List<String> localIps;
  final List<String> localIp6s;
  final StunStatus stunStatus;
  final String? errorMessage;
  final StunConfig? stunConfig;
  final String? ipLocation;
  final String? natType;
  final String? natMetadata;

  const SelfInfo({
    this.publicIp,
    this.publicPort,
    this.publicIp6,
    this.publicPort6,
    this.localIp,
    this.localPort,
    this.localPort6,
    this.localIps = const [],
    this.localIp6s = const [],
    this.stunStatus = StunStatus.loading,
    this.errorMessage,
    this.stunConfig,
    this.ipLocation,
    this.natType,
    this.natMetadata,
  });

  bool get hasIPv6 => localIp6s.isNotEmpty || publicIp6 != null;

  String get publicAddress =>
      (publicIp != null && publicPort != null) ? '$publicIp:$publicPort' : '';

  String get publicAddress6 =>
      (publicIp6 != null && publicPort6 != null)
          ? '[$publicIp6]:$publicPort6'
          : '';

  String get localAddress =>
      (localIp != null && localPort != null) ? '$localIp:$localPort' : '';

  String get natTypeDisplay {
    if (natType == null) return '';
    if (natType == 'cone') return '锥形 NAT（易穿透）';
    if (natType == 'sym') return '对称型 NAT（难穿透）';
    return natType!;
  }

  String get natTypeShort {
    if (natType == null) return '';
    if (natType == 'cone') return '锥形 NAT';
    if (natType == 'sym') return '对称型 NAT';
    return natType!;
  }

  bool get isSymmetricNat => natType == 'sym';

  int? get natPortStep {
    if (natMetadata == null) return null;
    final match = RegExp(r'd=(\d+)').firstMatch(natMetadata!);
    if (match != null) return int.tryParse(match.group(1)!);
    return null;
  }

  int? get natPortVelocity {
    if (natMetadata == null) return null;
    final match = RegExp(r'v=(\d+)').firstMatch(natMetadata!);
    if (match != null) return int.tryParse(match.group(1)!);
    return null;
  }

  /// Port parity: 0=even, 1=odd, null=mixed/unknown
  int? get natPortParity {
    if (natMetadata == null) return null;
    final match = RegExp(r'p=(\d+)').firstMatch(natMetadata!);
    if (match != null) return int.tryParse(match.group(1)!);
    return null;
  }

  int? get natProbeTimestamp {
    if (natMetadata == null) return null;
    final match = RegExp(r't=(\d+)').firstMatch(natMetadata!);
    if (match != null) return int.tryParse(match.group(1)!);
    return null;
  }

  /// All candidate addresses with NAT metadata appended after "|".
  /// IPv4: "ip:port", IPv6: "[ip]:port"
  /// Format: "localIp1:localPort,...,[ipv6]:port,...,publicIp:publicPort|natMetadata"
  String get candidateString {
    if (localPort == null) return publicAddress;
    final parts = <String>[];

    // IPv4 local addresses
    for (final lip in localIps) {
      parts.add('$lip:$localPort');
    }

    // IPv6 local addresses (global-scope only)
    final effectivePort6 = localPort6 ?? localPort;
    if (effectivePort6 != null) {
      for (final lip6 in localIp6s) {
        parts.add('[$lip6]:$effectivePort6');
      }
    }

    // IPv4 public address
    if (publicIp != null && publicPort != null) {
      parts.add('$publicIp:$publicPort');
    }

    // IPv6 public address
    if (publicIp6 != null && publicPort6 != null) {
      parts.add('[$publicIp6]:$publicPort6');
    }

    final addrPart = parts.join(',');
    if (natMetadata != null && natMetadata!.isNotEmpty) {
      return '$addrPart|$natMetadata';
    }
    return addrPart;
  }

  SelfInfo copyWith({
    String? publicIp,
    int? publicPort,
    String? publicIp6,
    int? publicPort6,
    String? localIp,
    int? localPort,
    int? localPort6,
    List<String>? localIps,
    List<String>? localIp6s,
    StunStatus? stunStatus,
    String? errorMessage,
    StunConfig? stunConfig,
    String? ipLocation,
    String? natType,
    String? natMetadata,
    bool clearError = false,
    bool clearIpLocation = false,
    bool clearNat = false,
    bool clearIpv6 = false,
  }) {
    return SelfInfo(
      publicIp: publicIp ?? this.publicIp,
      publicPort: publicPort ?? this.publicPort,
      publicIp6: clearIpv6 ? null : (publicIp6 ?? this.publicIp6),
      publicPort6: clearIpv6 ? null : (publicPort6 ?? this.publicPort6),
      localIp: localIp ?? this.localIp,
      localPort: localPort ?? this.localPort,
      localPort6: localPort6 ?? this.localPort6,
      localIps: localIps ?? this.localIps,
      localIp6s: localIp6s ?? this.localIp6s,
      stunStatus: stunStatus ?? this.stunStatus,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      stunConfig: stunConfig ?? this.stunConfig,
      ipLocation:
          clearIpLocation ? null : (ipLocation ?? this.ipLocation),
      natType: clearNat ? null : (natType ?? this.natType),
      natMetadata: clearNat ? null : (natMetadata ?? this.natMetadata),
    );
  }
}
