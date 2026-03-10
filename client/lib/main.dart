import 'package:flutter/material.dart';

import 'package:p2p_test/app/app.dart';
import 'package:p2p_test/utils/logger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.init();
  AppLogger.info('Main', 'P2PTest starting...');
  runApp(const P2PTestApp());
}
