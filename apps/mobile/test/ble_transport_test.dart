import 'dart:async';
import 'dart:convert';

import 'package:espface/core/session/session.dart';
import 'package:espface/core/session/token_store.dart';
import 'package:espface/core/transport/ble_framer.dart';
import 'package:espface/core/transport/ble_gatt.dart';
import 'package:espface/core/transport/ble_transport.dart';
import 'package:espface/core/transport/transport.dart';
import 'package:espface/features/render/ui_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';
import 'support/vectors.dart';

/// Fake GATT layer: the "peripheral" runs the firmware-side chunker/reassembler at [mtu].
class FakeGatt implements BleGatt {
  FakeGatt({this.mtu = 23, this.writeWithoutResponse = true, this.fail});
  int mtu;
  final bool writeWithoutResponse;
  final Object? fail;
  FakeChannel? channel;
  int opens = 0;

  @override
  Future<BleChannel> open(String id, {Duration timeout = const Duration(seconds: 20), int mtu = 512}) async {
    opens++;
    if (fail != null) throw fail!;
    return channel = FakeChannel(this.mtu, writeWithoutResponse);
  }
}

class FakeChannel implements BleChannel {
  FakeChannel(this._mtu, this.writeWithoutResponse);
  int _mtu;
  final BleChunker devTx = BleChunker();
  final BleReassembler devRx = BleReassembler();
  final List<String> received = [];
  final List<List<int>> packets = [];
  final List<bool> wnr = [];
  final notif = StreamController<List<int>>.broadcast();
  final mtuCtl = StreamController<int>.broadcast();
  final disc = StreamController<Object?>.broadcast();
  bool closed = false;

  @override
  int get mtu => _mtu;
  @override
  Stream<int> get mtuChanges => mtuCtl.stream;
  @override
  Stream<List<int>> get notifications => notif.stream;
  @override
  Stream<Object?> get disconnected => disc.stream;
  @override
  final bool writeWithoutResponse;

  /// Device sends one message chunked at the current MTU.
  void send(Map<String, dynamic> m) {
    devTx.setMtu(_mtu);
    for (final p in devTx.chunk(utf8.encode(jsonEncode(m)))) {
      notif.add(p);
    }
  }

  void changeMtu(int m) {
    _mtu = m;
    mtuCtl.add(m);
  }

  @override
  Future<void> write(List<int> packet, {required bool withoutResponse}) async {
    packets.add(packet);
    wnr.add(withoutResponse);
    if (devRx.feed(packet) == BleFeed.message) received.add(utf8.decode(devRx.message!));
  }

  @override
  Future<List<int>> readInfo() async => [...utf8.encode('Boiler'), 0, ...utf8.encode('a1b2c3')];
  @override
  Future<void> close() async => closed = true;
}

void main() {
  test('parseBleInfo', () {
    expect(parseBleInfo([...utf8.encode('Boiler'), 0, ...utf8.encode('a1b2c3')]), ('Boiler', 'a1b2c3'));
    expect(parseBleInfo(utf8.encode('noid')), isNull);
    expect(parseBleInfo([0]), isNull);
  });

  test('readBleInfo opens, reads INFO and disconnects', () async {
    final g = FakeGatt();
    expect(await readBleInfo('AA:BB', gatt: g), ('Boiler', 'a1b2c3'));
    expect(g.channel!.closed, isTrue);
  });

  test('connect: chunk size from the MTU, write-without-response, reassembly of chunked notifications', () async {
    final g = FakeGatt(mtu: 185);
    final t = BleTransport('AA:BB', gatt: g);
    final got = <String>[];
    t.messages.listen(got.add);
    final evs = <TransportState>[];
    t.events.listen((e) => evs.add(e.state));
    await t.connect();
    await settle();
    expect(evs, [TransportState.connecting, TransportState.open]);
    expect(t.isOpen, isTrue);
    expect(t.supportsBinary, isFalse);
    expect(t.payloadMax, 182);
    final ch = g.channel!;
    final big = jsonEncode({'t': 'set', 'id': 'x', 'v': 'y' * 400});
    expect(t.send(big), isTrue);
    await settle();
    expect(ch.packets.length, 3);
    expect(ch.packets.every((p) => p.length <= 185), isTrue);
    expect(ch.wnr, everyElement(isTrue));
    expect(ch.received, [big]);
    // device -> app, multi-chunk: receiving flag is up in between
    final ui = vectorMsg('ui full showcase');
    ch.devTx.setMtu(185);
    final pkts = ch.devTx.chunk(utf8.encode(jsonEncode(ui)));
    expect(pkts.length, greaterThan(3));
    ch.notif.add(pkts[0]);
    await settle();
    expect(t.receiving.value, isTrue);
    for (final p in pkts.sublist(1)) {
      ch.notif.add(p);
    }
    await settle();
    expect(t.receiving.value, isFalse);
    expect(got.length, 1);
    expect(jsonDecode(got.first), ui);
    // MTU renegotiation changes the chunk size
    ch.changeMtu(512);
    await settle();
    expect(t.payloadMax, 509);
    t.send(big);
    await settle();
    expect(ch.packets.length, 4);
    expect(ch.received.length, 2);
    await t.close();
    expect(ch.closed, isTrue);
  });

  test('write with response when the RX characteristic lacks write-no-response', () async {
    final g = FakeGatt(writeWithoutResponse: false);
    final t = BleTransport('AA:BB', gatt: g);
    await t.connect();
    t.send('{"t":"time"}');
    await settle();
    expect(g.channel!.wnr, [false]);
    await t.close();
  });

  test('peripheral disconnect -> closed event with reason', () async {
    final g = FakeGatt();
    final t = BleTransport('AA:BB', gatt: g);
    final evs = <TransportEvent>[];
    t.events.listen(evs.add);
    await t.connect();
    g.channel!.disc.add('link loss');
    await settle();
    expect(evs.last.state, TransportState.closed);
    expect(evs.last.error, 'link loss');
    expect(t.isOpen, isFalse);
    expect(t.send('{}'), isFalse);
    await t.close();
  });

  test('permission refusal surfaces as closed(PermissionDenied) and the session records it', () async {
    final g = FakeGatt(fail: const PermissionDenied('Bluetooth'));
    final s = Session(transportFactory: () => BleTransport('AA:BB', gatt: g), tokens: MemoryTokenStore(), store: UiStore(), backoff: (_) => const Duration(seconds: 30));
    s.start();
    await settle();
    expect(s.state, ConnState.offline);
    expect(s.lastError, isA<PermissionDenied>());
    s.dispose();
  });

  test('full session over BLE at mtu 23: hello -> ready, time sent as packets', () async {
    final g = FakeGatt(mtu: 23);
    final store = UiStore();
    final s = Session(transportFactory: () => BleTransport('AA:BB', gatt: g), tokens: MemoryTokenStore(), store: store, deviceId: 'a1b2c3');
    s.start();
    await settle();
    final ch = g.channel!;
    expect(ch.received.single, startsWith('{"t":"hello"'));
    ch.send(vectorMsg('device hello no auth'));
    await settle();
    expect(s.state, ConnState.ready);
    expect(store.device!.name, 'Boiler');
    expect(ch.received.last, startsWith('{"t":"time"'));
    expect(ch.packets.every((p) => p.length <= 23), isTrue);
    s.dispose();
  });
}
