// Hardening against fake devices started with the knobs of tools/fake-device, over real WebSockets.
// Gated per device: ESPFACE_FAKE_WS_DROP (--pin=1234 --drop-every 8), ESPFACE_FAKE_WS_SLOW (--slow-ui),
// ESPFACE_FAKE_WS_HUGE (--huge-ui), ESPFACE_FAKE_WS_BUSY (--max-clients 1), ESPFACE_FAKE_WS_FLAKY (--pin=1234 --flaky-auth).
import 'dart:async';
import 'dart:io';

import 'package:espface/core/session/session.dart';
import 'package:espface/core/session/token_store.dart';
import 'package:espface/core/transport/ws_transport.dart';
import 'package:espface/features/render/ui_store.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> waitFor(bool Function() cond, {Duration timeout = const Duration(seconds: 15), String what = 'condition'}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  final env = Platform.environment;
  final pin = env['ESPFACE_FAKE_PIN'] ?? '1234';
  const fast = Duration(milliseconds: 50);

  (Session, UiStore, List<ConnState>) connect(String url, {TokenStore? tokens}) {
    final store = UiStore();
    final log = <ConnState>[];
    final s = Session(transportFactory: () => WsTransport(Uri.parse(url)), tokens: tokens ?? MemoryTokenStore(), store: store, backoff: (_) => fast);
    s.addListener(() => log.add(s.state));
    s.start();
    return (s, store, log);
  }

  Future<void> pair(Session s) async {
    await waitFor(() => s.state == ConnState.pin || s.state == ConnState.ready, what: 'hello');
    if (s.state == ConnState.pin) {
      s.submitPin(pin);
      await waitFor(() => s.state == ConnState.ready, what: 'auth');
    }
  }

  test('drop-every: reconnects with the token, keeps the UI, never asks for the PIN again', () async {
    final url = env['ESPFACE_FAKE_WS_DROP'];
    if (url == null || url.isEmpty) return;
    final (s, store, log) = connect(url);
    await pair(s);
    await waitFor(() => store.widgets.isNotEmpty, what: 'ui');
    final n = store.widgets.length;
    await waitFor(() => s.state == ConnState.offline, timeout: const Duration(seconds: 30), what: 'drop');
    expect(store.widgets.length, n);
    await waitFor(() => s.state == ConnState.ready, what: 'reconnect');
    expect(store.widgets.length, n);
    await waitFor(() => s.state == ConnState.offline, timeout: const Duration(seconds: 30), what: 'second drop');
    await waitFor(() => s.state == ConnState.ready, what: 'second reconnect');
    expect(log.where((x) => x == ConnState.pin).length, 1);
    expect(s.attempts, greaterThanOrEqualTo(2));
    await s.stop();
  }, skip: (env['ESPFACE_FAKE_WS_DROP'] ?? '').isEmpty ? 'ESPFACE_FAKE_WS_DROP not set' : null);

  test('slow-ui: the fragmented ui arrives complete', () async {
    final url = env['ESPFACE_FAKE_WS_SLOW']!;
    final (s, store, _) = connect(url);
    await pair(s);
    var layouts = 0;
    store.listen('layout').addListener(() => layouts++);
    await waitFor(() => store.widgets.length >= 40, timeout: const Duration(seconds: 40), what: 'ui');
    expect(layouts, 1);
    expect(store.pages().map((p) => p.id), ['main', 'io', 'setup']);
    await s.stop();
  }, skip: (env['ESPFACE_FAKE_WS_SLOW'] ?? '').isEmpty ? 'ESPFACE_FAKE_WS_SLOW not set' : null);

  test('huge-ui: hundreds of widgets are applied and laid out quickly', () async {
    final url = env['ESPFACE_FAKE_WS_HUGE']!;
    final (s, store, _) = connect(url);
    final sw = Stopwatch();
    store.listen('device').addListener(sw.start);
    await pair(s);
    await waitFor(() => store.widgets.length > 400, timeout: const Duration(seconds: 30), what: 'ui');
    sw.stop();
    final t = Stopwatch()..start();
    final pages = store.pages();
    t.stop();
    // ignore: avoid_print
    print('huge-ui: ${store.widgets.length} widgets received+applied ${sw.elapsedMilliseconds} ms after hello, layout ${t.elapsedMicroseconds} us');
    expect(pages.length, 5);
    expect(t.elapsedMilliseconds, lessThan(100));
    s.page('p1');
    await waitFor(() => store.values.containsKey('w200'), what: 'page upd');
    await s.stop();
  }, skip: (env['ESPFACE_FAKE_WS_HUGE'] ?? '').isEmpty ? 'ESPFACE_FAKE_WS_HUGE not set' : null);

  test('max-clients: the second session is busy until the first leaves', () async {
    final url = env['ESPFACE_FAKE_WS_BUSY']!;
    final (a, _, _) = connect(url);
    await pair(a);
    final (b, bs, _) = connect(url);
    await waitFor(() => b.busy && b.state == ConnState.offline, what: 'busy');
    expect(bs.widgets, isEmpty);
    await a.stop();
    await waitFor(() => b.state == ConnState.ready, what: 'b ready');
    expect(b.busy, isFalse);
    await b.stop();
  }, skip: (env['ESPFACE_FAKE_WS_BUSY'] ?? '').isEmpty ? 'ESPFACE_FAKE_WS_BUSY not set' : null);

  test('flaky-auth: one PIN entry is enough', () async {
    final url = env['ESPFACE_FAKE_WS_FLAKY']!;
    final (s, _, log) = connect(url);
    await pair(s);
    expect(s.state, ConnState.ready);
    expect(log.where((x) => x == ConnState.pin).length, 1);
    await s.stop();
  }, skip: (env['ESPFACE_FAKE_WS_FLAKY'] ?? '').isEmpty ? 'ESPFACE_FAKE_WS_FLAKY not set' : null);
}
