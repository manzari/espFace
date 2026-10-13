import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/devices/devices_page.dart';
import '../features/devices/qr_scan_page.dart';
import '../features/render/device_screen.dart';
import '../features/system/system_page.dart';
import 'settings_page.dart';

final routerProvider = Provider<GoRouter>((ref) => GoRouter(
      routes: [
        GoRoute(path: '/', builder: (c, s) => const DevicesPage(), routes: [
          GoRoute(path: 'scan', builder: (c, s) => const QrScanPage()),
          GoRoute(path: 'settings', builder: (c, s) => const SettingsPage()),
          GoRoute(
            path: 'd/:key',
            builder: (c, s) => DeviceScreen(deviceKey: s.pathParameters['key']!),
            routes: [GoRoute(path: 'system', builder: (c, s) => SystemPage(deviceKey: s.pathParameters['key']!))],
          ),
        ]),
      ],
    ));
