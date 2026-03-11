import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:p2p_test/models/self_info.dart';
import 'package:p2p_test/services/ip_geo_service.dart';
import 'package:p2p_test/services/stun_service.dart';
import 'package:p2p_test/services/storage_service.dart';
import 'package:p2p_test/services/udp_service.dart';
import 'package:p2p_test/utils/logger.dart';

class SelfInfoProvider extends ChangeNotifier {
  static const String _tag = 'SelfInfoProvider';

  final UdpService _udpService;
  final StorageService _storageService;
  final IpGeoService _ipGeoService;

  SelfInfo _selfInfo = const SelfInfo();

  /// The STUN server that succeeded, used for keepalive.
  String? _activeStunHost;
  int? _activeStunPort;

  SelfInfoProvider({
    required UdpService udpService,
    required StorageService storageService,
    required IpGeoService ipGeoService,
  })  : _udpService = udpService,
        _storageService = storageService,
        _ipGeoService = ipGeoService;

  SelfInfo get selfInfo => _selfInfo;
  StunStatus get stunStatus => _selfInfo.stunStatus;
  String get publicAddress => _selfInfo.publicAddress;
  String get localAddress => _selfInfo.localAddress;
  String get candidateString => _selfInfo.candidateString;
  String? get errorMessage => _selfInfo.errorMessage;
  String? get ipLocation => _selfInfo.ipLocation;
  String? get natType => _selfInfo.natType;
  String? get natMetadata => _selfInfo.natMetadata;

  Future<void> initialize() async {
    _selfInfo = _selfInfo.copyWith(stunStatus: StunStatus.loading);
    notifyListeners();

    try {
      final localPort = await _udpService.bind();
      final localIps = await _getAllLocalIps();
      final localIp = localIps.isNotEmpty ? localIps.first : null;
      _selfInfo = _selfInfo.copyWith(
        localPort: localPort,
        localIp: localIp,
        localIps: localIps,
      );

      final config = await _storageService.loadStunConfig();
      if (config != null) {
        _selfInfo = _selfInfo.copyWith(stunConfig: config);
      }

      await fetchPublicAddress(stunServer: config?.selectedServer);
    } catch (e) {
      AppLogger.error(_tag, 'Initialization failed', e);
      _selfInfo = _selfInfo.copyWith(
        stunStatus: StunStatus.failed,
        errorMessage: e.toString(),
      );
      notifyListeners();
    }
  }

  /// Query ALL STUN servers to detect NAT type, then display last result.
  Future<void> fetchPublicAddress({String? stunServer}) async {
    _selfInfo = _selfInfo.copyWith(
      stunStatus: StunStatus.loading,
      clearError: true,
      clearNat: true,
    );
    notifyListeners();

    if (!_udpService.isBound) {
      _selfInfo = _selfInfo.copyWith(
        stunStatus: StunStatus.failed,
        errorMessage: 'UDP socket not bound',
      );
      notifyListeners();
      return;
    }

    _udpService.pauseKeepalive();
    try {
      final analysis = await StunService.analyzeNat(
        _udpService,
        preferredServer: stunServer,
      );

      final lastResult = analysis.lastResult;
      _activeStunHost = lastResult.stunHost;
      _activeStunPort = lastResult.stunPort;

      _selfInfo = _selfInfo.copyWith(
        publicIp: lastResult.publicIp,
        publicPort: lastResult.publicPort,
        stunStatus: StunStatus.success,
        natType: analysis.natType,
        natMetadata: analysis.metadata,
        clearError: true,
        clearIpLocation: true,
      );
      AppLogger.info(_tag,
          'Public address: ${_selfInfo.publicAddress}, NAT: ${analysis.metadata}');
      notifyListeners();

      _queryIpLocation(lastResult.publicIp);

      await _udpService.setKeepaliveStunServer(
          lastResult.stunHost, lastResult.stunPort);

      return;
    } catch (e) {
      AppLogger.error(_tag, 'Failed to fetch public address', e);
      _selfInfo = _selfInfo.copyWith(
        stunStatus: StunStatus.failed,
        errorMessage: e.toString(),
      );
      _udpService.resumeKeepalive();
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    _activeStunHost = null;
    _activeStunPort = null;
    await fetchPublicAddress(stunServer: _selfInfo.stunConfig?.selectedServer);
  }

  Future<void> _queryIpLocation(String ip) async {
    try {
      final location = await _ipGeoService.queryLocation(ip);
      _selfInfo = _selfInfo.copyWith(ipLocation: location);
      notifyListeners();
      AppLogger.info(_tag, 'IP location: $location');
    } catch (e) {
      AppLogger.error(_tag, 'Failed to query IP location', e);
      _selfInfo = _selfInfo.copyWith(ipLocation: '未知');
      notifyListeners();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  static Future<List<String>> _getAllLocalIps() async {
    final ips = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            ips.add(addr.address);
          }
        }
      }
    } catch (e) {
      AppLogger.warning(_tag, 'Failed to get local IPs: $e');
    }
    return ips;
  }
}
