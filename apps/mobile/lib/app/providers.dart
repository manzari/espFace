import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/session/session.dart';
import '../core/session/token_store.dart';
import '../core/transport/ble_transport.dart';
import '../core/transport/bt_classic_transport.dart';
import '../core/transport/transport.dart';
import '../core/transport/transport_chooser.dart';
import '../core/transport/usb_serial_transport.dart';
import '../core/transport/ws_transport.dart';
import '../features/devices/device.dart';
import '../features/devices/devices_repository.dart';
import '../features/render/ui_store.dart';
import 'flavor.dart';

/// Overridden in main() with the loaded instance.
final prefsProvider = Provider<SharedPreferences>((_) => throw UnimplementedError('prefsProvider must be overridden'));

final flavorProvider = Provider<Flavor>((_) => Flavor.fromEnvironment());

final tokenStoreProvider = Provider<TokenStore>((_) => SecureTokenStore());

/// USB OTG and Bluetooth Classic exist on Android only (PLAN 6.1); tests override this.
final serialSupportedProvider = Provider<bool>((_) => Platform.isAndroid);

/// Builds the transport for one medium of a saved device.
Transport makeTransport(SavedDevice d, TransportKind kind) => switch (kind) {
      TransportKind.wifi => WsTransport.host(d.host),
      TransportKind.ble => BleTransport(d.bleId!),
      TransportKind.usb => UsbSerialTransport(d.usbPort!, baud: d.usbBaud),
      TransportKind.bt => BtClassicTransport(d.btAddress!),
    };

/// Tests override this with fake transports.
final transportFactoryProvider = Provider<Transport Function(SavedDevice d, TransportKind kind)>((_) => makeTransport);

String _transportSig(SavedDevice d, bool serial) => '${d.candidates(serialSupported: serial)}|${d.host}|${d.bleId}|${d.usbPort}|${d.usbBaud}|${d.btAddress}';

/// Store + session for one saved device; lives while any screen of that device is shown.
class SessionBundle {
  SessionBundle({required this.store, required this.session, required this.chooser});
  final UiStore store;
  final Session session;
  final TransportChooser chooser;
}

final sessionProvider = Provider.autoDispose.family<SessionBundle, String>((ref, key) {
  final repo = ref.read(devicesProvider.notifier);
  final dev = repo.byKey(key);
  if (dev == null) throw StateError('unknown device $key');
  final serial = ref.read(serialSupportedProvider);
  final make = ref.read(transportFactoryProvider);
  final chooser = TransportChooser(kinds: dev.candidates(serialSupported: serial), make: (k) => make(repo.byKey(key) ?? dev, k));
  final store = UiStore();
  final session = Session(
    transportFactory: chooser.create,
    tokens: ref.read(tokenStoreProvider),
    store: store,
    deviceId: dev.id,
  );
  void onDevice() {
    final h = store.device;
    if (h != null) repo.learn(key, h);
  }

  var sig = _transportSig(dev, serial);
  ref.listen(devicesProvider, (_, list) {
    final d = list.where((x) => x.key == key).firstOrNull;
    if (d == null) return;
    final s = _transportSig(d, serial);
    if (s == sig) return;
    sig = s;
    chooser.setKinds(d.candidates(serialSupported: serial));
    session.reconnect();
  });

  // Backgrounded app: no reconnect attempts (they would only burn device slots and battery); resume reconnects.
  final lifecycle = AppLifecycleListener(onStateChange: (s) => session.setBackground(s != AppLifecycleState.resumed && s != AppLifecycleState.inactive));
  store.listen('device').addListener(onDevice);
  session.start();
  ref.onDispose(() {
    lifecycle.dispose();
    store.listen('device').removeListener(onDevice);
    session.dispose();
    chooser.dispose();
  });
  return SessionBundle(store: store, session: session, chooser: chooser);
});
