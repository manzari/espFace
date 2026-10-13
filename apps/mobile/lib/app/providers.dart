import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/session/session.dart';
import '../core/session/token_store.dart';
import '../core/transport/ws_transport.dart';
import '../features/devices/devices_repository.dart';
import '../features/render/ui_store.dart';
import 'flavor.dart';

/// Overridden in main() with the loaded instance.
final prefsProvider = Provider<SharedPreferences>((_) => throw UnimplementedError('prefsProvider must be overridden'));

final flavorProvider = Provider<Flavor>((_) => Flavor.fromEnvironment());

final tokenStoreProvider = Provider<TokenStore>((_) => SecureTokenStore());

/// Store + session for one saved device; lives while any screen of that device is shown.
class SessionBundle {
  SessionBundle({required this.store, required this.session});
  final UiStore store;
  final Session session;
}

final sessionProvider = Provider.autoDispose.family<SessionBundle, String>((ref, key) {
  final dev = ref.read(devicesProvider.notifier).byKey(key);
  if (dev == null) throw StateError('unknown device $key');
  final store = UiStore();
  final session = Session(
    transportFactory: () => WsTransport.host(dev.host),
    tokens: ref.read(tokenStoreProvider),
    store: store,
    deviceId: dev.id,
  );
  void onDevice() {
    final h = store.device;
    if (h != null) ref.read(devicesProvider.notifier).learn(key, h);
  }

  store.listen('device').addListener(onDevice);
  session.start();
  ref.onDispose(() {
    store.listen('device').removeListener(onDevice);
    session.dispose();
  });
  return SessionBundle(store: store, session: session);
});
