enum StunStatus {
  loading,
  success,
  failed,
  configuring,
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
  final StunStatus stunStatus;
  final String? errorMessage;
  final StunConfig? stunConfig;
  final String? ipLocation;

  const SelfInfo({
    this.publicIp,
    this.publicPort,
    this.localIp,
    this.localPort,
    this.stunStatus = StunStatus.loading,
    this.errorMessage,
    this.stunConfig,
    this.ipLocation,
  });

  String get publicAddress =>
      (publicIp != null && publicPort != null) ? '$publicIp:$publicPort' : '';

  String get localAddress =>
      (localIp != null && localPort != null) ? '$localIp:$localPort' : '';

  SelfInfo copyWith({
    String? publicIp,
    int? publicPort,
    String? localIp,
    int? localPort,
    StunStatus? stunStatus,
    String? errorMessage,
    StunConfig? stunConfig,
    String? ipLocation,
    bool clearError = false,
    bool clearIpLocation = false,
  }) {
    return SelfInfo(
      publicIp: publicIp ?? this.publicIp,
      publicPort: publicPort ?? this.publicPort,
      localIp: localIp ?? this.localIp,
      localPort: localPort ?? this.localPort,
      stunStatus: stunStatus ?? this.stunStatus,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      stunConfig: stunConfig ?? this.stunConfig,
      ipLocation:
          clearIpLocation ? null : (ipLocation ?? this.ipLocation),
    );
  }
}
