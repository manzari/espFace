// Store screenshots: renders the real app against a scripted device (demo UI of tools/fake-device) and writes
// 1080x1920 PNGs to fastlane/metadata/android/en-US/images/phoneScreenshots when ESPFACE_SCREENSHOTS=1.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:espface/app/app.dart';
import 'package:espface/app/providers.dart';
import 'package:espface/app/router.dart';
import 'package:espface/core/session/token_store.dart';
import 'package:espface/features/devices/device.dart';
import 'package:espface/features/devices/devices_repository.dart';
import 'package:espface/features/render/device_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';
import 'support/vectors.dart';

const _out = 'fastlane/metadata/android/en-US/images/phoneScreenshots';
final _write = Platform.environment['ESPFACE_SCREENSHOTS'] == '1';
final _t0 = DateTime.utc(2026, 10, 1, 9, 30).millisecondsSinceEpoch;

final _demoUi = <Map<String, dynamic>>[
  {'id': 'main', 'ty': 'page', 'lbl': 'Boiler', 'icon': 'home'},
  {'id': 'io', 'ty': 'page', 'lbl': 'I/O', 'icon': 'tune'},
  {'id': 'setup', 'ty': 'page', 'lbl': 'Setup', 'icon': 'settings'},
  {'id': 'sensors', 'ty': 'group', 'lbl': 'Sensors'},
  {'id': 'temp', 'ty': 'gauge', 'lbl': 'Temperature', 'min': 0, 'max': 120, 'unit': '°C', 'style': 'round', 'zones': [{'from': 90, 'to': 120, 'color': '#ff0000'}], 'grp': 'sensors', 'ro': true},
  {'id': 'tchart', 'ty': 'chart', 'lbl': 'Temp history', 'series': [{'id': 'temp', 'lbl': 'Temp', 'color': '#ff8800'}, {'id': 'target', 'lbl': 'Target', 'color': '#0088ff'}], 'win': 600, 'unit': '°C', 'legend': true, 'vals': true, 'grp': 'sensors'},
  {'id': 'level', 'ty': 'progress', 'lbl': 'Tank', 'min': 0, 'max': 100, 'grp': 'sensors'},
  {'id': 'disp', 'ty': 'display', 'lbl': 'Pressure', 'digits': 5, 'unit': 'bar', 'grp': 'sensors'},
  {'id': 'ok', 'ty': 'led', 'lbl': 'Burner', 'color': '#00c853', 'grp': 'sensors'},
  {'id': 'control', 'ty': 'group', 'lbl': 'Control'},
  {'id': 'r1', 'ty': 'row', 'grp': 'control'},
  {'id': 'pump', 'ty': 'switch', 'lbl': 'Pump', 'on': 'ON', 'off': 'OFF', 'row': 'r1', 'size': 2, 'grp': 'control'},
  {'id': 'target', 'ty': 'slider', 'lbl': 'Target', 'min': 20, 'max': 90, 'step': 1, 'unit': '°C', 'row': 'r1', 'size': 3, 'grp': 'control'},
  {'id': 'mode', 'ty': 'select', 'lbl': 'Mode', 'opts': ['Off', 'Auto', 'Manual'], 'style': 'seg', 'grp': 'control'},
  {'id': 'n', 'ty': 'number', 'lbl': 'Cycles', 'min': 0, 'max': 10, 'step': 1, 'spin': true, 'grp': 'control'},
  {'id': 'reset', 'ty': 'button', 'lbl': 'Reset error', 'hint': 'Clears the error latch', 'icon': 'restart_alt', 'grp': 'control'},
  {'id': 'term', 'ty': 'log', 'lbl': 'Log', 'rows': 6, 'cap': 200},
  {'id': 'inputs', 'ty': 'group', 'lbl': 'Inputs', 'page': 'io'},
  {'id': 'joy', 'ty': 'joystick', 'lbl': 'Valve', 'center': true, 'sq': true, 'grp': 'inputs', 'page': 'io'},
  {'id': 'col', 'ty': 'color', 'lbl': 'Light', 'grp': 'inputs', 'page': 'io'},
  {'id': 'start', 'ty': 'datetime', 'lbl': 'Start', 'mode': 'time', 'grp': 'inputs', 'page': 'io'},
  {'id': 'days', 'ty': 'flags', 'lbl': 'Days', 'opts': ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'], 'grp': 'inputs', 'page': 'io'},
  {'id': 'tbl', 'ty': 'table', 'lbl': 'Zones', 'cols': [{'lbl': 'Zone', 'w': 2, 'align': 'left'}, {'lbl': '°C', 'w': 1, 'align': 'right'}], 'page': 'io'},
  {'id': 'help', 'ty': 'textblock', 'text': 'Set the target and enable the pump.', 'page': 'setup'},
  {'id': 'name', 'ty': 'text', 'lbl': 'Name', 'maxlen': 32, 'page': 'setup'},
];

final _values = <String, dynamic>{
  'temp': 61.1, 'level': 70, 'disp': 1.85, 'ok': true, 'pump': true, 'target': 65, 'mode': 1, 'n': 3,
  'joy': [0, 0], 'col': 0xff8800, 'start': 6 * 3600, 'days': 31,
  'tbl': [['Kitchen', 21.5], ['Bath', 23.0], ['Hall', 19.8]], 'name': 'Boiler',
};

/// Answers like a firmware device: hello (open or PIN), ui + values + chart history, sys info/wifi.status.
class _DemoDevice extends FakeTransport {
  _DemoDevice({required this.pin});
  final bool pin;

  @override
  bool send(String text) {
    final ok = super.send(text);
    final m = sent.last;
    Future<void>.microtask(() => _answer(m));
    return ok;
  }

  void _answer(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'hello':
        if (pin) {
          receive({...vectorMsg('device hello pin required with nonce'), 'name': 'Garage door', 'id': 'c0ffee'});
          return;
        }
        receive(vectorMsg('device hello no auth'));
        receive({'t': 'ui', 'rev': 1, 'w': _demoUi});
        receive({'t': 'upd', 'v': _values});
        receive({
          't': 'pts', 'id': 'tchart', 's': 'temp',
          'p': [for (var i = 0; i < 60; i++) [_t0 + i * 10000, 48 + 16 * (1 - 1 / (1 + i / 10)) + 0.6 * math.sin(i / 2.5)]],
        });
        receive({'t': 'pts', 'id': 'tchart', 's': 'target', 'p': [for (var i = 0; i < 60; i += 6) [_t0 + i * 10000, i < 18 ? 60 : 65]]});
        for (final l in ['boot ok, fw 1.2.0', 'wifi connected: Home (-61 dBm)', 'burner on', 'target 60 -> 65 °C']) {
          receive({'t': 'log', 'id': 'term', 'msg': l});
        }
      case 'sys':
        if (m['cmd'] == 'info') receive(vectorMsg('sys info reply'));
        if (m['cmd'] == 'wifi.status') receive(vectorMsg('sys wifi.status push'));
    }
  }
}

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/sdks/flutter';
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  Future<void> load(String family, Iterable<File> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await l.load();
  }

  final all = dir.listSync().whereType<File>().toList();
  await load('Roboto', all.where((f) => f.path.split('/').last.startsWith('Roboto-')));
  await load('MaterialIcons', all.where((f) => f.path.endsWith('MaterialIcons-Regular.otf')));
  final mono = File('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf');
  if (mono.existsSync()) await load('monospace', [mono]);
}

final _pageScroll = find.descendant(of: find.byType(DeviceScreen), matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)).first;

void main() {
  setUpAll(_loadFonts);

  Future<ProviderContainer> boot(WidgetTester t, {required bool dark, bool pin = false}) async {
    t.view.physicalSize = const Size(1080, 1920);
    t.view.devicePixelRatio = 2.625;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
    t.platformDispatcher.platformBrightnessTestValue = dark ? Brightness.dark : Brightness.light;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [
      prefsProvider.overrideWithValue(prefs),
      tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
      serialSupportedProvider.overrideWithValue(true),
      transportFactoryProvider.overrideWithValue((d, k) => _DemoDevice(pin: pin || d.name == 'Garage door')),
    ]);
    final repo = c.read(devicesProvider.notifier);
    for (final d in [
      const SavedDevice(key: 'h:10.0.0.5', host: '10.0.0.5', name: 'Boiler', id: 'a1b2c3', proj: 'Home', icon: 'thermostat', fw: '1.2.0'),
      const SavedDevice(key: 'h:10.0.0.12', host: '10.0.0.12', name: 'Garage door', id: 'c0ffee', proj: 'Home', icon: 'garage', fw: '1.0.3', bleId: 'AA:BB:CC:00:11:22'),
      const SavedDevice(key: 'h:livingroom.local', host: 'livingroom.local', name: 'Living room lights', id: 'b16b00', proj: 'Home', icon: 'lightbulb', fw: '2.0.1'),
      const SavedDevice(key: 'h:10.0.0.31', host: '10.0.0.31', name: 'Greenhouse', id: '9a7e11', proj: 'Garden', icon: 'yard', fw: '0.9.0', bleId: 'AA:BB:CC:00:33:55'),
      const SavedDevice(key: 'u:303a:1001', name: 'Weather station', id: '5ea7e2', proj: 'Garden', icon: 'air', usbPort: '303a:1001'),
      const SavedDevice(key: 'h:10.0.0.60', host: '10.0.0.60', name: 'Bench PSU', id: '0dd5e7', proj: 'Lab', icon: 'bolt', fw: '1.1.0'),
    ]) {
      repo.upsert(d);
    }
    await t.pumpWidget(UncontrolledProviderScope(container: c, child: const RepaintBoundary(child: EspFaceApp())));
    await t.pump();
    return c;
  }

  Future<void> shot(WidgetTester t, String name) async {
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));
    if (!_write) return;
    final boundary = t.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    await t.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 2.625);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<void> go(WidgetTester t, ProviderContainer c, String path) async {
    c.read(routerProvider).go(path);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
  }

  Future<void> finish(WidgetTester t, ProviderContainer c) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
    c.dispose();
  }

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('device list ($mode)', (t) async {
      final c = await boot(t, dark: dark);
      expect(find.text('Greenhouse'), findsOneWidget);
      await shot(t, '${dark ? 5 : 1}_devices_$mode');
      await finish(t, c);
    });
  }

  testWidgets('device page with gauge, chart and controls (light), scrolled controls (dark)', (t) async {
    final c = await boot(t, dark: false);
    await go(t, c, '/d/${Uri.encodeComponent('h:10.0.0.5')}');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('Temp history'), findsOneWidget);
    await shot(t, '2_device_light');
    await finish(t, c);
  });

  testWidgets('device controls (dark)', (t) async {
    final c = await boot(t, dark: true);
    await go(t, c, '/d/${Uri.encodeComponent('h:10.0.0.5')}');
    await t.pump(const Duration(milliseconds: 300));
    await t.scrollUntilVisible(find.text('Reset error'), 300, scrollable: _pageScroll);
    expect(find.text('Pump'), findsWidgets);
    await shot(t, '6_controls_dark');
    await finish(t, c);
  });

  testWidgets('inputs page (light)', (t) async {
    final c = await boot(t, dark: false);
    await go(t, c, '/d/${Uri.encodeComponent('h:10.0.0.5')}');
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('I/O').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Valve'), findsOneWidget);
    await shot(t, '3_inputs_light');
    await finish(t, c);
  });

  testWidgets('system page (dark)', (t) async {
    final c = await boot(t, dark: true);
    await go(t, c, '/d/${Uri.encodeComponent('h:10.0.0.5')}');
    await t.pump(const Duration(milliseconds: 300));
    await go(t, c, '/d/${Uri.encodeComponent('h:10.0.0.5')}/system');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('ESP32-S3'), findsWidgets);
    await shot(t, '7_system_dark');
    await finish(t, c);
  });

  testWidgets('PIN pairing dialog (light)', (t) async {
    final c = await boot(t, dark: false);
    await go(t, c, '/d/${Uri.encodeComponent('h:10.0.0.12')}');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('asks for a PIN'), findsOneWidget);
    await t.enterText(find.byType(TextField), '1234');
    await shot(t, '4_pin_light');
    await finish(t, c);
  });
}
