enum StunStatus {
  loading,
  success,
  failed,
  configuring,
}

enum NatType {
  unknown,
  cone,
  symmetric,
}

extension NatTypeDisplay on NatType {
  String get label {
    switch (this) {
      case NatType.unknown:
        return 'NAT 类型未知';
      case NatType.cone:
        return '锥形 NAT';
      case NatType.symmetric:
        return '对称型 NAT';
    }
  }

  String get shortLabel {
    switch (this) {
      case NatType.unknown:
        return '未知';
      case NatType.cone:
        return '锥形';
      case NatType.symmetric:
        return '对称型';
    }
  }

  String get hint {
    switch (this) {
      case NatType.unknown:
        return '无法判断 NAT 类型';
      case NatType.cone:
        return 'P2P 打洞成功率高';
      case NatType.symmetric:
        return 'P2P 打洞困难，已启用端口预测';
    }
  }
}

extension NatPredictionInfo on SelfInfo {
  String get portPredictionHint {
    if (natType != NatType.symmetric) return natType.hint;
    final delta = portDelta;
    if (delta == null) return 'P2P 打洞困难，端口预测（无 delta 数据）';
    if (isConsistentDelta) {
      return 'P2P 打洞困难，端口预测 delta=$delta（规律分配，高置信）';
    }
    return 'P2P 打洞困难，端口预测 delta=$delta（不规律分配，扩大范围）';
  }
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
  final NatType natType;
  final int? portDelta;
  final bool isConsistentDelta;

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
    this.natType = NatType.unknown,
    this.portDelta,
    this.isConsistentDelta = false,
  });

  String get publicAddress =>
      (publicIp != null && publicPort != null) ? '$publicIp:$publicPort' : '';

  /// Public address with NAT metadata appended, for sharing/copying.
  String get publicAddressWithMeta {
    final addr = publicAddress;
    if (addr.isEmpty) return addr;
    return '$addr${_natMetaSuffix}';
  }

  String get localAddress =>
      (localIp != null && localPort != null) ? '$localIp:$localPort' : '';

  String get _natMetaSuffix {
    if (natType == NatType.symmetric) {
      final meta = StringBuffer('|sym');
      if (portDelta != null) meta.write(',d=$portDelta');
      meta.write(',c=${isConsistentDelta ? 1 : 0}');
      return meta.toString();
    }
    if (natType == NatType.cone) return '|cone';
    return '';
  }

  /// All candidate addresses + optional NAT metadata.
  /// Format: "localIp1:localPort,...,publicIp:publicPort[|natMeta]"
  /// NAT metadata examples: "|sym,d=2,c=1"  "|cone"
  String get candidateString {
    if (localPort == null) return publicAddress;
    final parts = <String>[];
    for (final lip in localIps) {
      parts.add('$lip:$localPort');
    }
    if (publicIp != null && publicPort != null) {
      parts.add('$publicIp:$publicPort');
    }
    return '${parts.join(",")}$_natMetaSuffix';
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
    NatType? natType,
    int? portDelta,
    bool? isConsistentDelta,
    bool clearError = false,
    bool clearIpLocation = false,
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
      natType: natType ?? this.natType,
      portDelta: portDelta ?? this.portDelta,
      isConsistentDelta: isConsistentDelta ?? this.isConsistentDelta,
    );
  }
}
