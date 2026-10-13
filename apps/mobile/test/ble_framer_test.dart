import 'dart:typed_data';

import 'package:espface/core/transport/ble_framer.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List msg(int n, [int seed = 0]) => Uint8List.fromList(List.generate(n, (i) => (i * 7 + seed) & 0xff));

/// Feeds every packet; returns the results in order.
List<BleFeed> feedAll(BleReassembler r, Iterable<List<int>> pkts) => [for (final p in pkts) r.feed(p)];

void main() {
  group('BleChunker', () {
    test('mtu clamps to 23..512 and payload is mtu-3', () {
      final c = BleChunker(mtu: 10);
      expect(c.payloadMax, 20);
      c.setMtu(1000);
      expect(c.payloadMax, 509);
      c.setMtu(185);
      expect(c.payloadMax, 182);
    });

    test('flags: first on the first packet, last on the last, both on a single one', () {
      final c = BleChunker(mtu: 23);
      final one = c.chunk(msg(20));
      expect(one.length, 1);
      expect(one.first[1], bleFlagFirst | bleFlagLast);
      final many = c.chunk(msg(45));
      expect(many.length, 3);
      expect(many[0][1], bleFlagFirst);
      expect(many[1][1], 0);
      expect(many[2][1], bleFlagLast);
      expect(many.map((p) => p[0]), [1, 2, 3]);
      expect(many[2].length, 2 + 5);
    });

    test('empty message is one empty first|last packet', () {
      final p = BleChunker(mtu: 512).chunk(const []);
      expect(p.length, 1);
      expect(p.first.length, 2);
      expect(p.first[1], 3);
    });
  });

  group('roundtrip', () {
    for (final mtu in [23, 185, 512]) {
      test('mtu $mtu', () {
        final c = BleChunker(mtu: mtu);
        final r = BleReassembler(cap: 8192);
        final m = msg(5000);
        final pkts = c.chunk(m);
        expect(pkts.length, (5000 / (mtu - 3)).ceil());
        for (final p in pkts) {
          expect(p.length, lessThanOrEqualTo(mtu));
        }
        final res = feedAll(r, pkts);
        expect(res.sublist(0, res.length - 1), everyElement(BleFeed.none));
        expect(res.last, BleFeed.message);
        expect(r.message, m);
        expect(r.partial, isFalse);
        // second message continues the seq counter
        final m2 = msg(10, 3);
        final res2 = feedAll(r, c.chunk(m2));
        expect(res2, [BleFeed.message]);
        expect(r.message, m2);
      });
    }
  });

  test('seq wraps 255 -> 0 inside one message', () {
    final c = BleChunker(mtu: 23);
    final r = BleReassembler(cap: 8192);
    final m = msg(6000);
    final pkts = c.chunk(m);
    expect(pkts.length, 300);
    expect(pkts[255][0], 255);
    expect(pkts[256][0], 0);
    expect(c.seq, 300 % 256);
    expect(feedAll(r, pkts).last, BleFeed.message);
    expect(r.message, m);
  });

  test('duplicate packet is ignored, message intact', () {
    final c = BleChunker(mtu: 23);
    final r = BleReassembler();
    final m = msg(100);
    final pkts = c.chunk(m);
    expect(r.feed(pkts[0]), BleFeed.none);
    expect(r.feed(pkts[1]), BleFeed.none);
    expect(r.feed(pkts[1]), BleFeed.none);
    expect(feedAll(r, pkts.sublist(2)).last, BleFeed.message);
    expect(r.message, m);
  });

  test('gap drops the partial message until the next first chunk', () {
    final c = BleChunker(mtu: 23);
    final r = BleReassembler();
    final pkts = c.chunk(msg(100));
    expect(r.feed(pkts[0]), BleFeed.none);
    expect(r.feed(pkts[1]), BleFeed.none);
    expect(r.feed(pkts[3]), BleFeed.dropped);
    expect(r.partial, isFalse);
    expect(r.feed(pkts[4]), BleFeed.dropped);
    final m2 = msg(30, 9);
    expect(feedAll(r, c.chunk(m2)), [BleFeed.none, BleFeed.message]);
    expect(r.message, m2);
  });

  test('continuation without an open message is dropped', () {
    final r = BleReassembler();
    expect(r.feed([5, 0, 1, 2]), BleFeed.dropped);
    expect(r.feed([6, bleFlagLast, 1]), BleFeed.dropped);
    expect(r.feed([1]), BleFeed.dropped);
  });

  test('oversize is reported once and the rest of that message is skipped', () {
    final c = BleChunker(mtu: 23);
    final r = BleReassembler(cap: 50);
    final pkts = c.chunk(msg(150));
    final res = feedAll(r, pkts);
    expect(res.where((x) => x == BleFeed.oversize).length, 1);
    expect(res.indexOf(BleFeed.oversize), 2);
    expect(res.sublist(3), everyElement(BleFeed.none));
    expect(r.partial, isFalse);
    final m2 = msg(40, 1);
    expect(feedAll(r, c.chunk(m2)).last, BleFeed.message);
    expect(r.message, m2);
  });

  test('exactly payloadMax bytes is a single packet', () {
    final c = BleChunker(mtu: 512);
    final p = c.chunk(msg(509));
    expect(p.length, 1);
    expect(p.first.length, 511);
    expect(p.first[1], 3);
  });
}
