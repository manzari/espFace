import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:espface/core/proto/hmac.dart';
import 'package:espface/core/session/session.dart';
import 'package:espface/core/session/token_store.dart';
import 'package:espface/core/transport/line_framer.dart';
import 'package:espface/core/transport/stream_transport.dart';
import 'package:espface/core/transport/transport.dart';
import 'package:espface/features/render/ui_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';
import 'support/vectors.dart';

/// In-memory serial wire with a scripted device on the far end (PIN pairing, then the showcase ui).
class FakeSerialDevice {
  FakeSerialDevice({this.pin = '1234'});
  final String pin;
  final LineFramer framer = LineFramer();
  final List<String> received = [];
  final List<String> raw = [];
  StreamController<Uint8List>? toApp;
  int opens = 0;
  int closes = 0;

  Future<ByteLink> open() async {
    opens++;
    toApp = StreamController<Uint8List>();
    return _Link(this);
  }

  void emitRaw(String s) => toApp?.add(Uint8List.fromList(utf8.encode(s)));
  void emit(Map<String, dynamic> m) => emitRaw('${jsonEncode(m)}\n');
  void dropLink() => toApp?.close();

  void onBytes(Uint8List data) {
    raw.add(utf8.decode(data));
    for (final ev in framer.feed(data)) {
      if (ev is! LineText) continue;
      received.add(ev.text);
      final m = jsonDecode(ev.text) as Map;
      switch (m['t']) {
        case 'hello':
          emit(vectorMsg('device hello pin required with nonce'));
        case 'auth':
          final ok = m['mac'] == hmacPin(pin, '00112233445566778899aabbccddeeff', 'a1b2c3');
          emit(ok ? vectorMsg('device auth ok') : {'t': 'auth', 'ok': false, 'left': 2});
          if (ok) emit(vectorMsg('ui full showcase'));
      }
    }
  }
}

class _Link implements ByteLink {
  _Link(this.dev);
  final FakeSerialDevice dev;
  @override
  Stream<Uint8List> get input => dev.toApp!.stream;
  @override
  Future<void> write(Uint8List data) async => dev.onBytes(data);
  @override
  Future<void> close() async {
    dev.closes++;
    await dev.toApp?.close();
  }
}

void main() {
  late FakeSerialDevice dev;
  late UiStore store;
  late Session s;
  final tokens = MemoryTokenStore();

  setUp(() {
    dev = FakeSerialDevice();
    store = UiStore();
    s = Session(
      transportFactory: () => StreamTransport(label: 'mem://0', opener: dev.open),
      tokens: tokens,
      store: store,
      backoff: (_) => const Duration(milliseconds: 10),
    );
  });

  tearDown(() => s.dispose());

  test('hello -> auth -> ui over a line-framed byte pipe', () async {
    s.start();
    await settle();
    expect(s.transport!.supportsBinary, isFalse);
    expect(s.sendBinary(Uint8List(3)), isFalse);
    expect(s.state, ConnState.pin);
    expect(dev.received.first, startsWith('{"t":"hello"'));
    s.submitPin('1234');
    await settle(10);
    expect(s.state, ConnState.ready);
    expect(store.device!.name, 'Boiler');
    expect(store.pages(), isNotEmpty);
    expect(await tokens.get('a1b2c3'), '0123456789abcdef0123456789abcdef');
    // every C2D message is one newline-terminated, newline-free line
    for (final chunk in dev.raw) {
      expect(chunk, endsWith('\n'));
      expect(chunk.substring(0, chunk.length - 1), isNot(contains('\n')));
    }
    expect(dev.received.map((l) => (jsonDecode(l) as Map)['t']), containsAllInOrder(['hello', 'auth', 'time']));
  });

  test('CRLF, boot noise and blank lines are ignored', () async {
    s.start();
    await settle();
    dev.emitRaw('ets Jul 29 2019 12:21:46\r\n\r\nrst:0x1 (POWERON_RESET)\r\n');
    dev.emitRaw('{"t":"toast","lvl":"info","msg":"hi"}\r\n');
    await settle();
    expect(store.toasts.map((t) => t.msg), ['hi']);
  });

  test('link drop closes the transport and the session reconnects on a fresh link', () async {
    s.start();
    await settle();
    expect(dev.opens, 1);
    final closed = <TransportEvent>[];
    s.transport!.events.listen(closed.add);
    dev.dropLink();
    await settle();
    expect(closed.map((e) => e.state), contains(TransportState.closed));
    expect(s.state, ConnState.offline);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await settle();
    expect(dev.opens, 2);
    expect(s.state, ConnState.pin);
  });

  test('open failure surfaces as closed with the error', () async {
    final t = StreamTransport(label: 'mem://x', opener: () async => throw const PermissionDenied('USB'));
    final evs = <TransportEvent>[];
    t.events.listen(evs.add);
    await t.connect();
    await settle();
    expect(evs.last.state, TransportState.closed);
    expect(evs.last.error, isA<PermissionDenied>());
    expect(t.send('{}'), isFalse);
    await t.close();
  });
}
