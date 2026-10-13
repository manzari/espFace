import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:espface/app/flavor.dart';
import 'package:espface/core/session/session.dart';
import 'package:espface/core/session/token_store.dart';
import 'package:espface/core/transport/ws_transport.dart';
import 'package:espface/features/devices/device.dart';
import 'package:espface/features/devices/discovery.dart';
import 'package:espface/features/render/ui_store.dart';
import 'package:espface/features/system/ota.dart';
import 'package:espface/features/system/release_check.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';
import 'support/vectors.dart';

void main() {
  group('flavor', () {
    test('defaults', () {
      final f = Flavor.parse();
      expect(f.appName, 'espFace');
      expect(f.accent, isNull);
      expect(f.proj, isNull);
      expect(f.locked, isFalse);
      expect(f.releaseCheckDefault, isFalse);
    });
    test('white-label values', () {
      final f = Flavor.parse(name: 'AcmeCtl', accent: '#112233', proj: 'Acme', devices: 'Boiler@10.0.0.5, Pump@pump.local:8080,', release: 'on');
      expect(f.appName, 'AcmeCtl');
      expect(f.accent!.toARGB32() & 0xffffff, 0x112233);
      expect(f.proj, 'Acme');
      expect(f.lockedDevices.map((d) => '${d.name}=${d.host}'), ['Boiler=10.0.0.5', 'Pump=pump.local:8080']);
      expect(f.releaseCheckDefault, isTrue);
      expect(Flavor.parse(accent: 'red').accent, isNull);
    });
  });

  group('discovery and QR', () {
    test('mDNS service mapping uses TXT id/name/proj/icon and address:port', () {
      final d = DiscoveryNotifier.fromService('boiler', 'boiler.local.', 8080, {'id': 'a1b2c3'.codeUnits, 'name': 'Boiler'.codeUnits, 'proj': 'Home'.codeUnits, 'icon': 'thermostat'.codeUnits, 'v': '1'.codeUnits}, addresses: ['192.168.1.50'])!;
      expect(d.id, 'a1b2c3');
      expect(d.name, 'Boiler');
      expect(d.host, '192.168.1.50:8080');
      expect(d.proj, 'Home');
      expect(d.icon, 'thermostat');
      expect(d.v, 1);
      expect(DiscoveryNotifier.fromService('x', 'x.local.', 80, null)!.host, 'x.local');
      expect(DiscoveryNotifier.fromService('x', null, 80, null), isNull);
    });
    test('QR url', () {
      final d = parseQr('espface://192.168.4.1?id=a1b2c3&name=Boiler&proj=Home')!;
      expect(d.host, '192.168.4.1');
      expect(d.id, 'a1b2c3');
      expect(d.name, 'Boiler');
      expect(parseQr('espface://boiler.local:8080')!.host, 'boiler.local:8080');
      expect(parseQr('https://example.com'), isNull);
      expect(parseQr('garbage'), isNull);
    });
    test('saved device json roundtrip and key', () {
      final d = SavedDevice(key: 'a1b2c3', host: '10.0.0.2', id: 'a1b2c3', name: 'Boiler', proj: 'Home', icon: 'thermostat', fw: '1.0', order: 2);
      expect(SavedDevice.fromJson(d.toJson())!.toJson(), d.toJson());
      expect(SavedDevice.keyFor(host: 'h'), 'host:h');
      expect(SavedDevice.keyFor(id: 'abc', host: 'h'), 'abc');
    });
  });

  group('ws url', () {
    test('host forms', () {
      expect(WsTransport.urlForHost('192.168.4.1').toString(), 'ws://192.168.4.1/ws');
      expect(WsTransport.urlForHost('boiler.local:8080').toString(), 'ws://boiler.local:8080/ws');
      expect(WsTransport.urlForHost('http://10.0.0.1/').toString(), 'ws://10.0.0.1/ws');
      expect(WsTransport.urlForHost('ws://10.0.0.1:81/custom').toString(), 'ws://10.0.0.1:81/custom');
      expect(WsTransport.urlForHost('ws://10.0.0.1').toString(), 'ws://10.0.0.1/ws');
    });
  });

  group('release check', () {
    test('parses latest release and compares versions', () {
      final r = ReleaseInfo.fromJson({'tag_name': 'v1.3.0', 'name': 'Autumn', 'html_url': 'u', 'assets': [{'name': 'notes.txt', 'browser_download_url': 'x'}, {'name': 'fw.bin', 'browser_download_url': 'https://dl/fw.bin'}]})!;
      expect(r.binUrl, 'https://dl/fw.bin');
      expect(r.isNewerThan('1.2.0'), isTrue);
      expect(r.isNewerThan('1.3.0'), isFalse);
      expect(r.isNewerThan('v1.10.0'), isFalse);
      expect(r.isNewerThan(null), isTrue);
      expect(ReleaseInfo.fromJson({'x': 1}), isNull);
    });
    test('refuses malformed repo without network', () async {
      expect(await fetchLatestRelease('../evil'), isNull);
    });
  });

  group('ota push', () {
    test('sends ota.begin with md5, chunks of 4096, resolves on ota.done', () async {
      late FakeTransport tr;
      final store = UiStore();
      final s = Session(transportFactory: () => tr = FakeTransport(), tokens: MemoryTokenStore(), store: store);
      s.start();
      await settle();
      tr.receive(vectorMsg('device hello no auth'));
      await settle();
      final image = Uint8List.fromList(List.generate(10000, (i) => i & 0xff));
      final ota = OtaPush(session: s, store: store);
      final run = ota.run(image);
      await settle();
      final begin = tr.last('sys')!;
      expect(begin['cmd'], 'ota.begin');
      expect(begin['size'], 10000);
      expect(begin['md5'], md5.convert(image).toString());
      tr.receive({'t': 'sys', 'cmd': 'ota.begin', 'ok': true});
      await settle(20);
      expect(tr.binary.map((b) => b.length), [4096, 4096, 1808]);
      expect(ota.sent, 10000);
      tr.receive({'t': 'sys', 'cmd': 'ota.progress', 'pct': 100});
      tr.receive({'t': 'sys', 'cmd': 'ota.done', 'ok': true});
      expect(await run, isTrue);
      expect(ota.error, isNull);
      expect(store.ota!.ok, isTrue);
      s.dispose();
    });
    test('refused begin reports an error', () async {
      late FakeTransport tr;
      final store = UiStore();
      final s = Session(transportFactory: () => tr = FakeTransport(), tokens: MemoryTokenStore(), store: store);
      s.start();
      await settle();
      tr.receive(vectorMsg('device hello no auth'));
      await settle();
      final ota = OtaPush(session: s, store: store);
      final run = ota.run(Uint8List(10));
      await settle();
      tr.receive({'t': 'sys', 'cmd': 'ota.begin', 'ok': false, 'msg': 'busy'});
      expect(await run, isFalse);
      expect(ota.error, 'busy');
      expect(tr.binary, isEmpty);
      s.dispose();
    });
  });
}
