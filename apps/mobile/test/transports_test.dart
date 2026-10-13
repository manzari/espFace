import 'package:espface/core/transport/transport.dart';
import 'package:espface/core/transport/transport_chooser.dart';
import 'package:espface/features/devices/device.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

void main() {
  group('SavedDevice transports', () {
    test('json roundtrip with every address and the pin', () {
      final d = SavedDevice(key: 'a1b2c3', host: '10.0.0.2', id: 'a1b2c3', name: 'Boiler', bleId: 'AA:BB:CC:DD:EE:FF', usbPort: '10c4:ea60', usbBaud: 921600, btAddress: '11:22:33:44:55:66', preferred: TransportKind.ble);
      final j = d.toJson();
      expect(j['ble'], 'AA:BB:CC:DD:EE:FF');
      expect(j['usb'], '10c4:ea60');
      expect(j['baud'], 921600);
      expect(j['bt'], '11:22:33:44:55:66');
      expect(j['pref'], 'ble');
      final back = SavedDevice.fromJson(j)!;
      expect(back.toJson(), j);
      expect(back.preferred, TransportKind.ble);
      expect(back.usbBaud, 921600);
    });

    test('phase 3 records (host only) keep their json shape; BLE-only records need no host', () {
      final old = SavedDevice(key: 'host:h', host: 'h', name: 'h').toJson();
      expect(old.keys, ['key', 'host', 'name', 'order']);
      expect(SavedDevice.fromJson({'key': 'ble:X', 'ble': 'X', 'name': 'S'})!.configured, [TransportKind.ble]);
      expect(SavedDevice.fromJson({'key': 'x', 'name': 'nothing'}), isNull);
      expect(SavedDevice.fromJson({'key': 'x', 'host': '', 'usb': '1:2'})!.name, 'x');
    });

    test('keyFor prefers the protocol id, then a medium prefix', () {
      expect(SavedDevice.keyFor(id: 'abc', bleId: 'X'), 'abc');
      expect(SavedDevice.keyFor(host: 'h', bleId: 'X'), 'host:h');
      expect(SavedDevice.keyFor(bleId: 'X'), 'ble:X');
      expect(SavedDevice.keyFor(usbPort: '1:2'), 'usb:1:2');
      expect(SavedDevice.keyFor(btAddress: 'M'), 'bt:M');
      expect(() => SavedDevice.keyFor(), throwsArgumentError);
    });

    test('candidates: WiFi -> BLE -> USB -> BT, serial hidden off Android, pin wins', () {
      final d = SavedDevice(key: 'k', host: 'h', name: 'n', bleId: 'B', usbPort: 'U', btAddress: 'M');
      expect(d.candidates(serialSupported: true), [TransportKind.wifi, TransportKind.ble, TransportKind.usb, TransportKind.bt]);
      expect(d.candidates(serialSupported: false), [TransportKind.wifi, TransportKind.ble]);
      expect(d.copyWith(preferred: TransportKind.usb).candidates(serialSupported: true), [TransportKind.usb]);
      // a pin for a medium this platform lacks falls back to auto
      expect(d.copyWith(preferred: TransportKind.usb).candidates(serialSupported: false), [TransportKind.wifi, TransportKind.ble]);
      expect(d.copyWith(preferred: null).preferred, isNull);
      expect(d.addressSummary, 'h · BLE · USB 115200 · BT');
    });

    test('merge adds addresses and replaces a placeholder name only', () {
      final wifi = SavedDevice(key: 'a1b2c3', host: '10.0.0.2', id: 'a1b2c3', name: 'Boiler', proj: 'Home');
      final ble = SavedDevice(key: 'a1b2c3', id: 'a1b2c3', name: 'Boiler BLE', bleId: 'B');
      final m = wifi.merge(ble);
      expect(m.host, '10.0.0.2');
      expect(m.bleId, 'B');
      expect(m.name, 'Boiler');
      expect(m.proj, 'Home');
      final placeholder = SavedDevice(key: 'ble:B', name: 'B', bleId: 'B');
      expect(placeholder.merge(SavedDevice(key: 'ble:B', name: 'Sensor', bleId: 'B', usbPort: 'U', usbBaud: 9600)).name, 'Sensor');
      expect(placeholder.merge(SavedDevice(key: 'ble:B', name: 'Sensor', bleId: 'B', usbPort: 'U', usbBaud: 9600)).usbBaud, 9600);
    });
  });

  group('TransportChooser', () {
    late Map<TransportKind, FakeTransport> made;
    late List<TransportKind> order;
    TransportChooser chooser(List<TransportKind> kinds) => TransportChooser(
          kinds: kinds,
          make: (k) {
            order.add(k);
            return made[k] = FakeTransport(autoOpen: false);
          },
        );

    setUp(() {
      made = {};
      order = [];
    });

    test('a medium that fails to open is rotated out, one that opened and dropped is retried first', () async {
      final c = chooser([TransportKind.wifi, TransportKind.ble, TransportKind.usb]);
      expect(c.next, TransportKind.wifi);
      final t1 = c.create();
      expect(c.active.value, TransportKind.wifi);
      await t1.connect();
      made[TransportKind.wifi]!.drop();
      await settle();
      expect(c.next, TransportKind.ble);
      final t2 = c.create();
      await t2.connect();
      made[TransportKind.ble]!.open();
      await settle();
      made[TransportKind.ble]!.drop();
      await settle();
      expect(c.next, TransportKind.ble);
      c.create();
      made[TransportKind.ble]!.drop();
      await settle();
      expect(c.next, TransportKind.usb);
      c.create();
      made[TransportKind.usb]!.drop();
      await settle();
      expect(c.next, TransportKind.wifi);
      expect(order, [TransportKind.wifi, TransportKind.ble, TransportKind.ble, TransportKind.usb]);
    });

    test('a single (pinned) kind never rotates; setKinds restarts from the front', () async {
      final c = chooser([TransportKind.usb]);
      c.create();
      made[TransportKind.usb]!.drop();
      await settle();
      expect(c.next, TransportKind.usb);
      expect(c.setKinds([TransportKind.usb]), isFalse);
      expect(c.setKinds([TransportKind.wifi, TransportKind.usb]), isTrue);
      expect(c.next, TransportKind.wifi);
      expect(c.kinds, [TransportKind.wifi, TransportKind.usb]);
    });

    test('no kinds -> create throws', () {
      expect(() => chooser([]).create(), throwsStateError);
    });
  });
}
