import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:p2p_test/models/self_info.dart';
import 'package:p2p_test/services/ip_geo_service.dart';
import 'package:p2p_test/services/storage_service.dart';
import 'package:p2p_test/services/stun_service.dart';
import 'package:p2p_test/services/udp_service.dart';
import 'package:p2p_test/utils/logger.dart';

class SelfInfoProvider extends ChangeNotifier {
  static const String _tag = 'SelfInfoProvider';

  final UdpService _udpService;
  final StorageService _storageService;
  final IpGeoService _ipGeoService;

  SelfInfo _selfInfo = const SelfInfo();

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
  String? get errorMessage => _selfInfo.errorMessage;
  String? get ipLocation => _selfInfo.ipLocation;

  Future<void> initialize() async {
    _selfInfo = _selfInfo.copyWith(stunStatus: StunStatus.loading);
    notifyListeners();

    try {
      // Bind UDP socket
      final localPort = await _udpService.bind();
      final localIp = await _getLocalIp();
      _selfInfo = _selfInfo.copyWith(localPort: localPort, localIp: localIp);

      // Load saved STUN config
      final config = await _storageService.loadStunConfig();
      if (config != null) {
        _selfInfo = _selfInfo.copyWith(stunConfig: config);
      }

      // Fetch public address
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

  Future<void> fetchPublicAddress({String? stunServer}) async {
    _selfInfo = _selfInfo.copyWith(
      stunStatus: StunStatus.loading,
      clearError: true,
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

    try {
      final result = await StunService.fetchPublicAddress(
        _udpService,
        preferredServer: stunServer,
      );
      _selfInfo = _selfInfo.copyWith(
        publicIp: result.publicIp,
        publicPort: result.publicPort,
        stunStatus: StunStatus.success,
        clearError: true,
        clearIpLocation: true,
      );
      AppLogger.info(_tag, 'Public address: ${_selfInfo.publicAddress}');
      notifyListeners();

      _queryIpLocation(result.publicIp);
      return;
    } catch (e) {
      AppLogger.error(_tag, 'Failed to fetch public address', e);
      _selfInfo = _selfInfo.copyWith(
        stunStatus: StunStatus.failed,
        errorMessage: e.toString(),
      );
    }
    notifyListeners();
  }

  void enterConfiguring() {
    _selfInfo = _selfInfo.copyWith(stunStatus: StunStatus.configuring);
    notifyListeners();
  }

  void cancelConfiguring() {
    _selfInfo = _selfInfo.copyWith(stunStatus: StunStatus.success);
    notifyListeners();
  }

  Future<void> saveStunConfig(String? server, bool isCustom) async {
    final config = StunConfig(
      selectedServer: server,
      isCustom: isCustom,
      updatedAt: DateTime.now(),
    );
    _selfInfo = _selfInfo.copyWith(stunConfig: config);
    await _storageService.saveStunConfig(config);
    notifyListeners();
  }

  Future<void> retryWithServer(String? server, bool isCustom) async {
    await saveStunConfig(server, isCustom);
    await fetchPublicAddress(stunServer: server);
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

  static Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      AppLogger.warning(_tag, 'Failed to get local IP: $e');
    }
    return null;
  }
}
