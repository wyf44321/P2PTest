import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:p2p_test/app/theme.dart';
import 'package:p2p_test/providers/peer_provider.dart';
import 'package:p2p_test/providers/self_info_provider.dart';
import 'package:p2p_test/screens/home_screen.dart';
import 'package:p2p_test/services/ip_geo_service.dart';
import 'package:p2p_test/services/monitor_service.dart';
import 'package:p2p_test/services/storage_service.dart';
import 'package:p2p_test/services/udp_service.dart';

class P2PTestApp extends StatefulWidget {
  const P2PTestApp({super.key});

  @override
  State<P2PTestApp> createState() => _P2PTestAppState();
}

class _P2PTestAppState extends State<P2PTestApp> with WidgetsBindingObserver {
  late final UdpService _udpService;
  late final StorageService _storageService;
  late final MonitorService _monitorService;
  late final IpGeoService _ipGeoService;
  late final SelfInfoProvider _selfInfoProvider;
  late final PeerProvider _peerProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initServices();
  }

  void _initServices() {
    _udpService = UdpService();
    _storageService = StorageService();
    _ipGeoService = IpGeoService();
    _monitorService = MonitorService(udpService: _udpService);

    _selfInfoProvider = SelfInfoProvider(
      udpService: _udpService,
      storageService: _storageService,
      ipGeoService: _ipGeoService,
    );

    _peerProvider = PeerProvider(
      monitorService: _monitorService,
      ipGeoService: _ipGeoService,
    );

    // Forward our own NAT type to MonitorService so it can adapt sending
    // strategy (avoid port scanning when we are behind symmetric NAT).
    _selfInfoProvider.addListener(() {
      _monitorService.setOwnNatType(_selfInfoProvider.natMetadata);
    });

    _startup();
  }

  Future<void> _startup() async {
    await _selfInfoProvider.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Save state when app goes to background
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _monitorService.stopAll();
    _udpService.close();
    _selfInfoProvider.dispose();
    _peerProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _selfInfoProvider),
        ChangeNotifierProvider.value(value: _peerProvider),
      ],
      child: MaterialApp(
        title: 'P2PTest',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        debugShowCheckedModeBanner: false,
        home: const HomeScreen(),
      ),
    );
  }
}
