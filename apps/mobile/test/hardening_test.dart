// Phase 6 hardening: backoff, token resume, busy/flaky devices, background handling, provider disposal,
// bounded buffers and the lazy layout for huge UIs.
import 'dart:convert';
import 'dart:math' as math;

import 'package:espface/app/providers.dart';
import 'package:espface/core/proto/codec.dart';
import 'package:espface/core/proto/hmac.dart';
import 'package:espface/core/proto/messages.dart';
import 'package:espface/core/session/session.dart';
import 'package:espface/core/session/token_store.dart';
import 'package:espface/core/transport/transport.dart';
import 'package:espface/features/devices/device.dart';
import 'package:espface/features/devices/devices_repository.dart';
import 'package:espface/features/render/layout.dart';
import 'package:espface/features/render/ui_store.dart';
import 'package:espface/features/render/widgets/registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';
import 'support/pump.dart';
import 'support/vectors.dart';

D2C decodeMsg(Map<String, dynamic> j) => decode(jsonEncode(j))!;

class _FixedRandom implements math.Random {
  _FixedRandom(this.v);
  final double v;
  @override
  bool nextBool() => v >= 0.5;
  @override
  double nextDouble() => v;
  @override
  int nextInt(int max) => (v * max).floor();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('backoff', () {
    test('500 ms * 2^n, capped at 30 s, +-25 % jitter', () {
      expect(backoffDelay(0, rng: _FixedRandom(0.5)), const Duration(milliseconds: 500));
      expect(backoffDelay(1, rng: _FixedRandom(0.5)), const Duration(seconds: 1));
      expect(backoffDelay(5, rng: _FixedRandom(0.5)), const Duration(seconds: 16));
      expect(backoffDelay(6, rng: _FixedRandom(0.5)), backoffCap);
      expect(backoffDelay(3, rng: _FixedRandom(0)), const Duration(seconds: 3));
      expect(backoffDelay(3, rng: _FixedRandom(1)), const Duration(seconds: 5));
      expect(backoffDelay(50, rng: _FixedRandom(1)), backoffCap);
      for (var a = 0; a < 40; a++) {
        final d = backoffDelay(a);
        expect(d.inMilliseconds, inInclusiveRange(375, backoffCap.inMilliseconds));
      }
    });
  });

  group('session hardening', () {
    late FakeTransport t;
    late MemoryTokenStore tokens;
    late UiStore store;
    late Session s;
    var created = 0;
    final states = <ConnState>[];

    Session make({Duration Function(int)? backoff}) {
      created = 0;
      states.clear();
      tokens = MemoryTokenStore();
      store = UiStore();
      s = Session(
        transportFactory: () {
          created++;
          return t = FakeTransport();
        },
        tokens: tokens,
        store: store,
        deviceId: 'a1b2c3',
        backoff: backoff ?? (_) => const Duration(milliseconds: 10),
      );
      s.addListener(() => states.add(s.state));
      return s;
    }

    setUp(() => make());
    tearDown(() => s.dispose());

    Future<void> pairAndLoad() async {
      s.start();
      await settle();
      t.receive(vectorMsg('device hello pin required with nonce'));
      await settle();
      s.submitPin('1234');
      t.receive(vectorMsg('device auth ok'));
      t.receive(vectorMsg('ui full showcase'));
      await settle();
      expect(s.state, ConnState.ready);
      expect(store.widgets, isNotEmpty);
    }

    test('a drop keeps the last UI, the token resumes the session and the PIN is never asked again', () async {
      await pairAndLoad();
      final n = store.widgets.length;
      t.receive({'t': 'sys', 'cmd': 'info', 'chip': 'ESP32'});
      await settle();
      expect(store.sysInfo, isNotNull);
      t.drop();
      await settle();
      expect(s.state, ConnState.offline);
      expect(store.widgets.length, n, reason: 'UI model survives the disconnect');
      expect(store.sysInfo, isNull, reason: 'per-connection state is reset');
      expect(s.retryAt, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await settle();
      expect(created, 2);
      expect(t.last('hello')!['tok'], '0123456789abcdef0123456789abcdef');
      t.receive(vectorMsg('device hello pin accepted by token'));
      await settle();
      expect(s.state, ConnState.ready);
      expect(states.where((x) => x == ConnState.pin).length, 1);
      expect(s.attempts, 1);
    });

    test('err 9 on hello marks the session busy until a hello succeeds', () async {
      s.start();
      await settle();
      t.receive({'t': 'err', 'code': 9, 'msg': 'too many clients', 'ref': 'hello'});
      await settle();
      expect(s.busy, isTrue);
      t.drop();
      await settle();
      expect(s.state, ConnState.offline);
      expect(s.busy, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await settle();
      expect(created, 2);
      t.receive(vectorMsg('device hello no auth'));
      await settle();
      expect(s.busy, isFalse);
      expect(s.state, ConnState.ready);
    });

    test('flaky auth: err 5 after a correct PIN is retried once with a fresh nonce, no second prompt', () async {
      s.start();
      await settle();
      t.receive(vectorMsg('device hello pin required with nonce'));
      await settle();
      s.submitPin('1234');
      expect(t.ofType('auth').length, 1);
      t.receive({'t': 'err', 'code': 5, 'msg': 'flaky', 'ref': 'auth'});
      await settle();
      expect(t.ofType('hello').length, 2, reason: 'asks for a new nonce');
      t.receive(vectorMsg('device hello pin required with nonce'));
      await settle();
      expect(t.ofType('auth').length, 2, reason: 'retries with the remembered PIN');
      expect(t.last('auth')!['mac'], hmacPin('1234', '00112233445566778899aabbccddeeff', 'a1b2c3'));
      t.receive(vectorMsg('device auth ok'));
      await settle();
      expect(s.state, ConnState.ready);
      expect(states.where((x) => x == ConnState.pin).length, 1);
    });

    test('a second err 5 goes back to the PIN prompt instead of looping', () async {
      s.start();
      await settle();
      t.receive(vectorMsg('device hello pin required with nonce'));
      await settle();
      s.submitPin('1234');
      t.receive({'t': 'err', 'code': 5, 'ref': 'auth'});
      await settle();
      t.receive(vectorMsg('device hello pin required with nonce'));
      await settle();
      t.receive({'t': 'err', 'code': 5, 'ref': 'auth'});
      await settle();
      expect(s.state, ConnState.pin);
      expect(t.ofType('auth').length, 2);
      expect(t.ofType('hello').length, 3);
    });

    test('background: no reconnects while backgrounded, immediate reconnect on resume', () async {
      s.start();
      await settle();
      t.receive(vectorMsg('device hello no auth'));
      await settle();
      s.setBackground(true);
      t.drop();
      await settle();
      expect(s.state, ConnState.offline);
      expect(s.retryAt, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(created, 1, reason: 'no retry in the background');
      s.setBackground(false);
      await settle();
      expect(created, 2, reason: 'foreground reconnects at once');
      t.receive(vectorMsg('device hello no auth'));
      await settle();
      expect(s.state, ConnState.ready);
    });

    test('backgrounding with an open link keeps it; a pending retry is cancelled', () async {
      make(backoff: (_) => const Duration(seconds: 5));
      s.start();
      await settle();
      t.receive(vectorMsg('device hello no auth'));
      await settle();
      s.setBackground(true);
      expect(s.state, ConnState.ready);
      expect(t.closed, isFalse);
      s.setBackground(false);
      expect(created, 1);
      t.drop();
      await settle();
      expect(s.retryAt, isNotNull);
      s.setBackground(true);
      expect(s.retryAt, isNull);
    });

    test('manual reconnect is immediate and replaces a pending slow retry', () async {
      make(backoff: (_) => const Duration(seconds: 5));
      s.start();
      await settle();
      t.receive(vectorMsg('device hello no auth'));
      await settle();
      t.drop();
      await settle();
      expect(s.retryAt!.difference(DateTime.now()).inSeconds, greaterThan(3));
      s.reconnect();
      await settle();
      expect(created, 2);
      expect(s.attempts, 2);
    });

    test('lockout carries a countdown and survives a drop', () async {
      s.start();
      await settle();
      t.receive(vectorMsg('device hello locked out'));
      await settle();
      expect(s.state, ConnState.locked);
      final left = s.lockUntil!.difference(DateTime.now()).inSeconds;
      expect(left, inInclusiveRange(40, 60));
      t.drop();
      await settle();
      expect(s.state, ConnState.locked);
    });

    test('dispose closes the transport, stops retries and never notifies again', () async {
      s.start();
      await settle();
      t.receive(vectorMsg('device hello no auth'));
      await settle();
      final before = states.length;
      s.dispose();
      await settle();
      expect(t.closed, isTrue);
      expect(s.transport, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(created, 1);
      expect(states.length, before);
      make(); // tearDown disposes this fresh one
    });
  });

  group('session provider', () {
    test('disposing the provider stops the session and closes its transport', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final fakes = <FakeTransport>[];
      final container = ProviderContainer(overrides: [
        prefsProvider.overrideWithValue(prefs),
        tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
        serialSupportedProvider.overrideWithValue(false),
        transportFactoryProvider.overrideWithValue((d, k) {
          final f = FakeTransport();
          fakes.add(f);
          return f;
        }),
      ]);
      addTearDown(container.dispose);
      final dev = container.read(devicesProvider.notifier).upsert(SavedDevice(key: SavedDevice.keyFor(host: '10.0.0.5'), host: '10.0.0.5', name: 'Boiler', id: 'a1b2c3'));
      final sub = container.listen(sessionProvider(dev.key), (_, _) {});
      final bundle = sub.read();
      await settle();
      expect(fakes.length, 1);
      expect(bundle.chooser.active.value, TransportKind.wifi);
      fakes.single.receive(vectorMsg('device hello no auth'));
      await settle();
      expect(bundle.session.state, ConnState.ready);
      expect(container.read(devicesProvider).single.name, 'Boiler');
      sub.close();
      await settle();
      expect(fakes.single.closed, isTrue);
      expect(bundle.session.transport, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(fakes.length, 1, reason: 'no reconnect after dispose');
    });
  });

  group('bounded buffers', () {
    late UiStore st;
    setUp(() => st = UiStore());
    void apply(Map<String, dynamic> j) => st.apply(decodeMsg(j));

    test('chart series never exceed the hard cap even with a huge window', () {
      apply({'t': 'hello', 'v': 1, 'name': 'x', 'id': 'a1b2c3', 'auth': 'none', 'ok': true, 'up': 0, 'caps': []});
      apply({'t': 'ui', 'rev': 1, 'w': [{'id': 'c', 'ty': 'chart', 'series': [{'id': 'a'}], 'win': 10000000}]});
      for (var i = 0; i < 12; i++) {
        apply({'t': 'pts', 'id': 'c', 's': 'a', 'p': [for (var k = 0; k < 1000; k++) [1099511627776 + i * 1000 + k, k]]});
      }
      expect(st.charts['c']!['a']!.length, chartMaxPoints);
    });

    test('log widgets are capped below an absurd device cap, dialogs at ten', () {
      apply({'t': 'ui', 'rev': 1, 'w': [{'id': 'l', 'ty': 'log', 'cap': 1000000}]});
      for (var i = 0; i < logMaxLines + 100; i++) {
        apply({'t': 'log', 'id': 'l', 'msg': 'x$i'});
      }
      expect(st.logs['l']!.length, logMaxLines);
      for (var i = 0; i < 15; i++) {
        apply({'t': 'dlg', 'id': 'd$i', 'kind': 'confirm', 'msg': '?'});
      }
      expect(st.dialogs.length, dialogCap);
    });

    test('buffers of widgets removed by a new ui are released', () {
      apply({'t': 'ui', 'rev': 1, 'w': [{'id': 'c', 'ty': 'chart', 'series': [{'id': 'a'}]}, {'id': 'l', 'ty': 'log'}]});
      apply({'t': 'pts', 'id': 'c', 's': 'a', 'p': [[1, 1]]});
      apply({'t': 'log', 'id': 'l', 'msg': 'x'});
      apply({'t': 'ui', 'rev': 2, 'w': [{'id': 'other', 'ty': 'label'}]});
      expect(st.charts, isEmpty);
      expect(st.logs, isEmpty);
    });
  });

  group('huge ui layout', () {
    testWidgets('a page with 600 widgets only builds what is on screen', (t) async {
      final store = UiStore();
      final actions = RecordingActions();
      final w = <Map<String, dynamic>>[{'id': 'p', 'ty': 'page', 'lbl': 'P'}, {'id': 'g', 'ty': 'group', 'lbl': 'Big', 'fold': true}];
      for (var i = 0; i < 600; i++) {
        w.add({'id': 'w$i', 'ty': i % 2 == 0 ? 'label' : 'switch', 'lbl': 'Widget $i', 'grp': 'g'});
      }
      store.apply(decodeMsg({'t': 'ui', 'rev': 1, 'w': w}));
      store.apply(decodeMsg({'t': 'upd', 'v': {for (var i = 0; i < 600; i++) 'w$i': i % 2 == 0 ? i : i % 4 == 1}}));
      final page = store.pages().single;
      final sw = Stopwatch()..start();
      await t.pumpWidget(scoped(store, actions, SizedBox(height: 500, child: PageBody(page: page))));
      await t.pump();
      sw.stop();
      final built = find.byType(WidgetView).evaluate().length;
      // ignore: avoid_print
      print('huge-ui layout: 600 widgets, first frame ${sw.elapsedMilliseconds} ms, $built widget views built');
      expect(built, lessThan(120));
      expect(find.text('Widget 0'), findsOneWidget);
      expect(find.text('Widget 599'), findsNothing);
      await t.scrollUntilVisible(find.text('Widget 599'), 1000, scrollable: find.byType(Scrollable).last, maxScrolls: 200);
      await t.pumpAndSettle();
      expect(find.text('Widget 599'), findsOneWidget);
      expect(find.byType(WidgetView).evaluate().length, lessThan(120));
      t.state<ScrollableState>(find.byType(Scrollable).last).position.jumpTo(0);
      await t.pumpAndSettle();
      await t.tap(find.text('Big'));
      await t.pump();
      expect(find.byType(WidgetView), findsNothing);
      await unmount(t);
    });
  });
}
