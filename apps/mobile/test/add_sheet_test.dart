import 'package:espface/app/providers.dart';
import 'package:espface/core/transport/transport.dart';
import 'package:espface/features/devices/device.dart';
import 'package:espface/features/devices/devices_page.dart';
import 'package:espface/features/devices/devices_repository.dart';
import 'package:espface/features/devices/discovery.dart';
import 'package:espface/features/devices/scan_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeDiscovery extends DiscoveryNotifier {
  @override
  List<DiscoveredDevice> build() => const [DiscoveredDevice(id: 'a1b2c3', name: 'Boiler', host: '10.0.0.5', proj: 'Home')];
}

class FakeBleScan extends BleScanNotifier {
  @override
  List<BleFound> build() => const [BleFound(bleId: 'AA:BB:CC:DD:EE:FF', name: 'espFace-sensor', rssi: -60)];
}

class _Home extends StatelessWidget {
  const _Home();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(child: FilledButton(onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const AddDeviceSheet()), child: const Text('Add'))),
      );
}

/// Spinners keep animating, so pumpAndSettle would never return: pump a fixed number of frames instead.
Future<void> frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<(ProviderContainer, GoRouter)> pump(WidgetTester tester, {bool serial = true}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const _Home()),
    GoRoute(path: '/d/:key', builder: (_, s) => Scaffold(body: Text('device ${s.pathParameters['key']}'))),
  ]);
  final container = ProviderContainer(overrides: [
    prefsProvider.overrideWithValue(prefs),
    serialSupportedProvider.overrideWithValue(serial),
    discoveryProvider.overrideWith(FakeDiscovery.new),
    bleScanProvider.overrideWith(FakeBleScan.new),
    usbPortsProvider.overrideWith((_) async => const [UsbPortInfo(port: '10c4:ea60', name: 'CP2102N USB to UART')]),
    btPairedProvider.overrideWith((_) async => const [BtPairedInfo(address: '11:22:33:44:55:66', name: 'ESP32-SPP')]),
    bleInfoReaderProvider.overrideWithValue((id) async => ('Boiler', 'a1b2c3')),
  ]);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
  await tester.pump();
  await tester.tap(find.text('Add'));
  await frames(tester);
  return (container, router);
}

void main() {
  testWidgets('WiFi section lists discovered devices and offers host entry and QR', (tester) async {
    await pump(tester);
    expect(find.text('Boiler'), findsOneWidget);
    expect(find.text('10.0.0.5 · Home'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Scan QR'), findsOneWidget);
    expect(find.text('USB'), findsOneWidget);
    expect(find.text('Bluetooth'), findsOneWidget);
  });

  testWidgets('BLE section: scan result, INFO read gives name and protocol id, record merges by id', (tester) async {
    final (container, router) = await pump(tester);
    await tester.tap(find.text('BLE'));
    await frames(tester);
    expect(find.text('espFace-sensor'), findsOneWidget);
    expect(find.textContaining('AA:BB:CC:DD:EE:FF'), findsOneWidget);
    await tester.tap(find.text('espFace-sensor'));
    await frames(tester);
    final devs = container.read(devicesProvider);
    expect(devs.single.key, 'a1b2c3');
    expect(devs.single.bleId, 'AA:BB:CC:DD:EE:FF');
    expect(devs.single.name, 'Boiler');
    expect(devs.single.configured, [TransportKind.ble]);
    expect(router.state.uri.path, '/d/a1b2c3');
    // later the same device is discovered over WiFi: addresses merge into one record
    container.read(devicesProvider.notifier).addDiscovered(const DiscoveredDevice(id: 'a1b2c3', name: 'Boiler', host: '10.0.0.5'));
    final merged = container.read(devicesProvider).single;
    expect(merged.host, '10.0.0.5');
    expect(merged.bleId, 'AA:BB:CC:DD:EE:FF');
    expect(merged.candidates(serialSupported: false), [TransportKind.wifi, TransportKind.ble]);
  });

  testWidgets('USB section: port list with baud choice', (tester) async {
    final (container, _) = await pump(tester);
    await tester.tap(find.text('USB'));
    await frames(tester);
    expect(find.text('CP2102N USB to UART'), findsOneWidget);
    expect(find.text('10c4:ea60'), findsOneWidget);
    await tester.tap(find.text('115200 baud'));
    await frames(tester);
    await tester.tap(find.text('921600 baud').last);
    await frames(tester);
    await tester.tap(find.text('CP2102N USB to UART'));
    await frames(tester);
    final d = container.read(devicesProvider).single;
    expect(d.key, 'usb:10c4:ea60');
    expect(d.usbPort, '10c4:ea60');
    expect(d.usbBaud, 921600);
    expect(d.candidates(serialSupported: true), [TransportKind.usb]);
  });

  testWidgets('Bluetooth section: paired devices', (tester) async {
    final (container, _) = await pump(tester);
    await tester.tap(find.text('Bluetooth'));
    await frames(tester);
    expect(find.text('ESP32-SPP'), findsOneWidget);
    await tester.tap(find.text('ESP32-SPP'));
    await frames(tester);
    final d = container.read(devicesProvider).single;
    expect(d.btAddress, '11:22:33:44:55:66');
    expect(d.key, 'bt:11:22:33:44:55:66');
  });

  testWidgets('serial sections are hidden where USB OTG / SPP do not exist (iOS)', (tester) async {
    await pump(tester, serial: false);
    expect(find.text('WiFi'), findsOneWidget);
    expect(find.text('BLE'), findsOneWidget);
    expect(find.text('USB'), findsNothing);
    expect(find.text('Bluetooth'), findsNothing);
  });
}
