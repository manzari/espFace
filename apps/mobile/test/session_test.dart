import 'package:espface/core/proto/hmac.dart';
import 'package:espface/core/session/session.dart';
import 'package:espface/core/session/token_store.dart';
import 'package:espface/features/render/ui_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';
import 'support/vectors.dart';

void main() {
  late FakeTransport t;
  late MemoryTokenStore tokens;
  late UiStore store;
  late Session s;
  var created = 0;

  setUp(() {
    created = 0;
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
      backoff: (_) => const Duration(milliseconds: 10),
    );
  });

  tearDown(() => s.dispose());

  test('open device: hello ok -> ready, time sent', () async {
    s.start();
    await settle();
    expect(t.last('hello'), {'t': 'hello', 'v': 1, 'client': 'app'});
    t.receive(vectorMsg('device hello no auth'));
    await settle();
    expect(s.state, ConnState.ready);
    expect(t.last('time')!['unix'], isA<int>());
    expect(store.device!.name, 'Boiler');
    expect(store.hasCap('wifi'), isTrue);
  });

  test('pin flow with the reference hmac, token stored and reused', () async {
    s.start();
    await settle();
    t.receive(vectorMsg('device hello pin required with nonce'));
    await settle();
    expect(s.state, ConnState.pin);
    s.submitPin('1234');
    expect(t.last('auth')!['mac'], hmacPin('1234', '00112233445566778899aabbccddeeff', 'a1b2c3'));
    t.receive(vectorMsg('device auth ok'));
    await settle();
    expect(s.state, ConnState.ready);
    expect(await tokens.get('a1b2c3'), '0123456789abcdef0123456789abcdef');
    expect(t.last('time'), isNotNull);

    t.drop();
    await settle();
    expect(s.state, ConnState.offline);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await settle();
    expect(created, 2);
    expect(t.last('hello')!['tok'], '0123456789abcdef0123456789abcdef');
    t.receive(vectorMsg('device hello pin accepted by token'));
    await settle();
    expect(s.state, ConnState.ready);
  });

  test('pin entered before the nonce is known triggers a fresh hello', () async {
    s.start();
    await settle();
    s.submitPin('1234');
    expect(t.ofType('hello').length, 2);
    t.receive(vectorMsg('device hello pin required with nonce'));
    await settle();
    expect(t.last('auth'), isNotNull);
  });

  test('wrong pin: attempts left, new hello for a fresh nonce', () async {
    s.start();
    await settle();
    t.receive(vectorMsg('device hello pin required with nonce'));
    await settle();
    s.submitPin('0000');
    t.receive(vectorMsg('device auth wrong with attempts left'));
    await settle();
    expect(s.state, ConnState.pin);
    expect(s.authLeft, 3);
    expect(t.ofType('hello').length, 2);
  });

  test('rejected token is forgotten', () async {
    await tokens.put('a1b2c3', 'deadbeefdeadbeefdeadbeefdeadbeef');
    s.start();
    await settle();
    expect(t.last('hello')!['tok'], 'deadbeefdeadbeefdeadbeefdeadbeef');
    t.receive(vectorMsg('device hello pin required with nonce'));
    await settle();
    expect(await tokens.get('a1b2c3'), isNull);
    expect(s.state, ConnState.pin);
  });

  test('token known only under the real id is retried once', () async {
    await tokens.put('a1b2c3', '0123456789abcdef0123456789abcdef');
    s.deviceId = null;
    s.start();
    await settle();
    expect(t.last('hello')!.containsKey('tok'), isFalse);
    t.receive(vectorMsg('device hello pin required with nonce'));
    await settle();
    expect(t.last('hello')!['tok'], '0123456789abcdef0123456789abcdef');
  });

  test('lockout from hello and from auth', () async {
    s.start();
    await settle();
    t.receive(vectorMsg('device hello locked out'));
    await settle();
    expect(s.state, ConnState.locked);
    expect(s.lockUntil!.isAfter(DateTime.now().add(const Duration(seconds: 30))), isTrue);
    t.drop();
    await settle();
    expect(s.state, ConnState.locked, reason: 'a drop while locked keeps the locked state');
  });

  test('auth lock', () async {
    s.start();
    await settle();
    t.receive(vectorMsg('device hello pin required with nonce'));
    await settle();
    s.submitPin('1');
    t.receive(vectorMsg('device auth locked'));
    await settle();
    expect(s.state, ConnState.locked);
  });

  test('active page is re-sent after reconnect', () async {
    s.start();
    await settle();
    t.receive(vectorMsg('device hello no auth'));
    t.receive(vectorMsg('ui full showcase'));
    await settle();
    s.page('setup');
    expect(t.last('page')!['id'], 'setup');
    t.drop();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await settle();
    t.receive(vectorMsg('device hello no auth'));
    await settle();
    expect(t.last('page')!['id'], 'setup');
  });

  test('set/ev/dlg/sys helpers encode and update the store', () async {
    s.start();
    await settle();
    t.receive(vectorMsg('device hello no auth'));
    await settle();
    s.set('pump', true);
    expect(store.values['pump'], isTrue);
    expect(t.last('set'), {'t': 'set', 'id': 'pump', 'v': true});
    s.ev('horn', 1);
    expect(t.last('ev'), {'t': 'ev', 'id': 'horn', 'v': 1});
    t.receive(vectorMsg('dlg confirm'));
    await settle();
    expect(store.dialogs.length, 1);
    s.dlg('d1', true);
    expect(store.dialogs, isEmpty);
    expect(t.last('dlg'), {'t': 'dlg', 'id': 'd1', 'ok': true});
    s.sys('info');
    expect(t.last('sys'), {'t': 'sys', 'cmd': 'info'});
  });

  test('stop closes the transport and stops reconnecting', () async {
    s.start();
    await settle();
    await s.stop();
    expect(t.closed, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(created, 1);
    expect(s.state, ConnState.stopped);
  });

  test('err messages become toasts, unknown messages are ignored', () async {
    s.start();
    await settle();
    t.receive(vectorMsg('device hello no auth'));
    t.receive({'t': 'err', 'code': 7, 'msg': 'bad value', 'ref': 'set'});
    t.receive({'t': 'hologram', 'x': 1});
    t.receiveRaw('not json');
    await settle();
    expect(store.toasts.single.msg, 'bad value (set) [7]');
    expect(s.state, ConnState.ready);
  });
}
