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
  final String? localIp;
  final int? localPort;
  final List<String> localIps;
  final StunStatus stunStatus;
  final String? errorMessage;
  final StunConfig? stunConfig;
  final String? ipLocation;
  final String? natType;
  final String? natMetadata;

  const SelfInfo({
    this.publicIp,
    this.publicPort,
    this.localIp,
    this.localPort,
    this.localIps = const [],
    this.stunStatus = StunStatus.loading,
    this.errorMessage,
    this.stunConfig,
    this.ipLocation,
    this.natType,
    this.natMetadata,
  });

  String get publicAddress =>
      (publicIp != null && publicPort != null) ? '$publicIp:$publicPort' : '';

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

  int? get natProbeTimestamp {
    if (natMetadata == null) return null;
    final match = RegExp(r't=(\d+)').firstMatch(natMetadata!);
    if (match != null) return int.tryParse(match.group(1)!);
    return null;
  }

  /// All candidate addresses with NAT metadata appended after "|".
  /// Format: "localIp1:localPort,...,publicIp:publicPort|natMetadata"
  String get candidateString {
    if (localPort == null) return publicAddress;
    final parts = <String>[];
    for (final lip in localIps) {
      parts.add('$lip:$localPort');
    }
    if (publicIp != null && publicPort != null) {
      parts.add('$publicIp:$publicPort');
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
    String? localIp,
    int? localPort,
    List<String>? localIps,
    StunStatus? stunStatus,
    String? errorMessage,
    StunConfig? stunConfig,
    String? ipLocation,
    String? natType,
    String? natMetadata,
    bool clearError = false,
    bool clearIpLocation = false,
    bool clearNat = false,
  }) {
    return SelfInfo(
      publicIp: publicIp ?? this.publicIp,
      publicPort: publicPort ?? this.publicPort,
      localIp: localIp ?? this.localIp,
      localPort: localPort ?? this.localPort,
      localIps: localIps ?? this.localIps,
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
