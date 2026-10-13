import 'dart:convert';

import 'package:espface/core/proto/codec.dart';
import 'package:espface/core/proto/hmac.dart';
import 'package:espface/core/proto/messages.dart';
import 'package:espface/core/proto/values.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/vectors.dart';

const _typed = {
  'hello': HelloMsg,
  'auth': AuthMsg,
  'ui': UiMsg,
  'upd': UpdMsg,
  'pts': PtsMsg,
  'toast': ToastMsg,
  'log': LogMsg,
  'prop': PropMsg,
  'dlg': DlgMsg,
  'sys': SysMsg,
  'err': ErrMsg,
};

void main() {
  final vectors = loadVectors();

  test('vectors are present (107 expected by the protocol suite)', () {
    expect(vectors.length, greaterThanOrEqualTo(100));
  });

  group('decode d2c vectors', () {
    for (final v in vectors.where((v) => v.dir == 'd2c' && v.valid)) {
      test('${v.file}: ${v.name}', () {
        final m = decode(jsonEncode(v.msg));
        expect(m, isNotNull);
        expect(m.runtimeType, _typed[v.msg['t']] ?? UnknownMsg);
      });
    }
  });

  group('decode never throws on invalid d2c vectors', () {
    for (final v in vectors.where((v) => v.dir == 'd2c' && !v.valid)) {
      test('${v.file}: ${v.name}', () {
        expect(() => decode(jsonEncode(v.msg)), returnsNormally);
      });
    }
  });

  test('decode rejects non-objects and missing t', () {
    expect(decode('nope'), isNull);
    expect(decode('[1,2]'), isNull);
    expect(decode('{"x":1}'), isNull);
    expect(decode('{"t":1}'), isNull);
    expect(decode('{"t":"future","x":1}'), isA<UnknownMsg>());
  });

  test('hmac reference vector', () {
    final v = vectors.firstWhere((v) => v.hmac != null);
    final h = v.hmac!;
    expect(hmacPin(h['pin'] as String, h['nonce'] as String, h['id'] as String), v.msg['mac']);
    expect(hmacPin('1234', '00112233445566778899aabbccddeeff', 'a1b2c3'), '03cc85f2b0409c8d81d2648f5f68c212d8feea811ba59f01908e213163e596a8');
  });

  group('c2d builders match vectors', () {
    Map<String, dynamic> roundtrip(Map<String, dynamic> m) => Map<String, dynamic>.from(jsonDecode(encode(m)) as Map);
    test('hello', () {
      expect(roundtrip(C2d.hello()), vectorMsg('client hello app without token'));
      expect(roundtrip(C2d.hello(tok: '0123456789abcdef0123456789abcdef', client: 'web')), vectorMsg('client hello web with token'));
    });
    test('auth', () => expect(roundtrip(C2d.auth('03cc85f2b0409c8d81d2648f5f68c212d8feea811ba59f01908e213163e596a8')), vectorMsg('client auth reference hmac')));
    test('time', () {
      final m = roundtrip(C2d.time(now: DateTime.fromMillisecondsSinceEpoch(1728700000000)));
      expect(m['t'], 'time');
      expect(m['unix'], 1728700000);
      expect(m['tz'], isA<int>());
    });
    test('set', () {
      expect(roundtrip(C2d.set('pump', true)), vectorMsg('set bool'));
      expect(roundtrip(C2d.set('target', 65.5)), vectorMsg('set number'));
      expect(roundtrip(C2d.set('note', 'hello')), vectorMsg('set string'));
      expect(roundtrip(C2d.set('joy', [-100, 100])), vectorMsg('set joystick'));
    });
    test('ev', () {
      expect(roundtrip(C2d.ev('reset')), vectorMsg('ev plain button'));
      expect(roundtrip(C2d.ev('horn', 1)), vectorMsg('ev hold press'));
      expect(roundtrip(C2d.ev('horn', 0)), vectorMsg('ev hold release'));
      expect(roundtrip(C2d.ev('pad', 'u')), vectorMsg('ev dpad up'));
    });
    test('dlg', () {
      expect(roundtrip(C2d.dlg('d1', true)), vectorMsg('dlg answer confirm yes'));
      expect(roundtrip(C2d.dlg('d2', true, 'Kitchen boiler')), vectorMsg('dlg answer prompt'));
      expect(roundtrip(C2d.dlg('d2', false, 'ignored')), vectorMsg('dlg answer cancel'));
    });
    test('page', () => expect(roundtrip(C2d.page('setup')), vectorMsg('page switch')));
    test('sys', () {
      expect(roundtrip(C2d.sys('info')), vectorMsg('sys info request'));
      expect(roundtrip(C2d.sys('wifi.set', {'ssid': 'Home', 'pass': 'secret'})), vectorMsg('sys wifi.set'));
      expect(roundtrip(C2d.sys('pin.set', {'pin': '4321'})), vectorMsg('sys pin.set'));
      expect(roundtrip(C2d.sys('ota.begin', {'size': 1048576, 'md5': 'd41d8cd98f00b204e9800998ecf8427e'})), vectorMsg('sys ota.begin'));
    });
  });

  group('widget model', () {
    test('ui full showcase parses every widget with typed props', () {
      final ui = decode(jsonEncode(vectorMsg('ui full showcase'))) as UiMsg;
      expect(ui.rev, 7);
      final byId = {for (final w in ui.widgets) w.id: w};
      expect(byId['temp']!.zones.single.color, '#ff0000');
      expect(byId['tchart']!.series.single.id, 'temp');
      expect(byId['target']!.sizeW, 3);
      expect(byId['sp']!.sizeH, 8);
      expect(byId['mode']!.opts, ['Off', 'Auto', 'Manual']);
      expect(byId['tbl']!.cols.first.w, 2);
      expect(byId['notes']!.dis, isTrue);
      expect(byId['notes']!.readOnly, isTrue);
      expect(byId['pos']!.zoom, 14);
    });
    test('defaults per PROTOCOL.md 5.2', () {
      final w = WidgetDef({'id': 'x', 'ty': 'slider'});
      expect(w.min, 0);
      expect(w.max, 100);
      expect(w.step, 1);
      expect(w.win, 300);
      expect(w.rows, 5);
      expect(w.cap, 200);
      expect(w.digits, 4);
      expect(w.zoom, 12);
      expect(w.mode, 'datetime');
      expect(w.legend, isTrue);
      expect(w.vals, isFalse);
      expect(w.vis, isTrue);
    });
    test('merge keeps id/ty and patches the rest', () {
      final w = WidgetDef({'id': 'x', 'ty': 'gauge', 'lbl': 'T', 'max': 100}).merge({'lbl': 'Hot', 'ty': 'label', 'id': 'y', 'vis': false});
      expect(w.id, 'x');
      expect(w.ty, 'gauge');
      expect(w.lbl, 'Hot');
      expect(w.max, 100);
      expect(w.vis, isFalse);
    });
  });

  group('values', () {
    test('fmtValue printf subset', () {
      expect(fmtValue(21.456), '21.46');
      expect(fmtValue(21.0), '21');
      expect(fmtValue(21.456, '%.1f'), '21.5');
      expect(fmtValue(7, '%03d'), '  7');
      expect(fmtValue(7, '%d%%'), '7%');
      expect(fmtValue('ok', '%s!'), 'ok!');
    });
    test('hex and decimals', () {
      expect(hexColor(0xff8800), '#ff8800');
      expect(hexColor(-5), '#000000');
      expect(decimals(1), 0);
      expect(decimals(0.1), 1);
      expect(decimals(0.25), 2);
    });
    test('formatClock', () {
      expect(formatClock(DateTime(2024, 10, 12, 9, 5, 7)), '09:05:07');
      expect(formatClock(DateTime(2024, 10, 12, 9, 5, 7), 'YYYY-MM-DD HH:mm'), '2024-10-12 09:05');
    });
  });
}
