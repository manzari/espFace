// Smoke test against the reference fake device over a real WebSocket.
// Gated: set ESPFACE_FAKE_WS=ws://host.docker.internal:18080/ws (docker) or ws://localhost:18080/ws.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:espface/core/session/session.dart';
import 'package:espface/core/session/token_store.dart';
import 'package:espface/core/transport/ws_transport.dart';
import 'package:espface/features/render/ui_store.dart';
import 'package:espface/features/system/ota.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> waitFor(bool Function() cond, {Duration timeout = const Duration(seconds: 10), String what = 'condition'}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  final url = Platform.environment['ESPFACE_FAKE_WS'];
  if (url == null || url.isEmpty) {
    test('fake device smoke test', () {}, skip: 'ESPFACE_FAKE_WS not set');
    return;
  }
  final pin = Platform.environment['ESPFACE_FAKE_PIN'] ?? '1234';
  final tokens = MemoryTokenStore();

  Session connect(UiStore store) => Session(transportFactory: () => WsTransport(Uri.parse(url)), tokens: tokens, store: store)..start();

  test('hello -> pin auth -> ui -> set switch -> upd echo -> sys info', () async {
    final store = UiStore();
    final s = connect(store);
    await waitFor(() => s.state == ConnState.pin || s.state == ConnState.ready, what: 'hello');
    if (s.state == ConnState.pin) {
      s.submitPin(pin);
      await waitFor(() => s.state == ConnState.ready, what: 'auth');
    }
    expect(store.device!.id, isNotEmpty);
    await waitFor(() => store.widgets.isNotEmpty, what: 'ui');
    expect(store.widgets.keys, containsAll(['pump', 'target', 'tchart', 'term']));
    expect(store.widgets.values.map((w) => w.ty).toSet().length, greaterThanOrEqualTo(25));
    await waitFor(() => store.values.containsKey('pump'), what: 'first upd');
    final before = store.values['pump'] == true;
    var echoes = 0;
    store.listen('v:pump').addListener(() => echoes++);
    expect(s.set('pump', !before), isTrue);
    await waitFor(() => echoes >= 2 && store.values['pump'] == !before, what: 'upd echo');
    s.sys('info');
    await waitFor(() => store.sysInfo != null, what: 'sys info');
    expect(store.sysInfo!.chip, isNotEmpty);
    await waitFor(() => (store.charts['tchart']?['temp']?.isNotEmpty ?? false), timeout: const Duration(seconds: 5), what: 'chart points');
    await waitFor(() => (store.logs['term']?.isNotEmpty ?? false), timeout: const Duration(seconds: 5), what: 'log lines');
    s.page('io');
    await waitFor(() => store.values.containsKey('joy'), what: 'page upd');
    await s.stop();
  });

  test('reconnect with the stored token skips the PIN', () async {
    final store = UiStore();
    final s = connect(store);
    await waitFor(() => s.state == ConnState.ready || s.state == ConnState.pin, what: 'hello');
    expect(s.state, ConnState.ready, reason: 'token from the first test must be accepted');
    await s.stop();
  });

  test('OTA push of a random image completes with ota.done ok', () async {
    final store = UiStore();
    final s = connect(store);
    await waitFor(() => s.state == ConnState.ready, what: 'ready');
    final rnd = Random(7);
    final image = Uint8List.fromList(List.generate(20000, (_) => rnd.nextInt(256)));
    final ota = OtaPush(session: s, store: store);
    expect(await ota.run(image), isTrue, reason: ota.error);
    expect(store.ota!.ok, isTrue);
    await s.stop();
  });
}
