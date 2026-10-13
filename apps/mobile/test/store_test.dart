import 'dart:convert';

import 'package:espface/core/proto/codec.dart';
import 'package:espface/core/proto/messages.dart';
import 'package:espface/features/render/ui_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/vectors.dart';

void main() {
  late UiStore st;
  var now = DateTime.fromMillisecondsSinceEpoch(1728700000000);
  D2C m(Map<String, dynamic> j) => decode(jsonEncode(j))!;
  void apply(Map<String, dynamic> j) => st.apply(m(j));

  setUp(() {
    now = DateTime.fromMillisecondsSinceEpoch(1728700000000);
    st = UiStore(now: () => now);
  });

  test('layout from the full showcase: pages, groups, rows, free blocks', () {
    apply(vectorMsg('ui full showcase'));
    final pages = st.pages();
    expect(pages.map((p) => p.id), ['main', 'setup']);
    expect(st.page, 'main');
    final main = pages.first;
    expect(main.blocks.map((b) => b.kind), ['free', 'group', 'group', 'free']);
    final sensors = main.blocks[1];
    expect(sensors.id, 'sensors');
    expect(sensors.items.whereType<WidgetItem>().map((i) => i.id), ['temp', 'tchart', 'level', 'bal', 'disp', 'ok', 'rgb']);
    final control = main.blocks[2];
    final row = control.items.whereType<RowLayout>().single;
    expect(row.id, 'r1');
    expect(row.items, ['pump', 'target']);
    expect(main.blocks[3].items.whereType<WidgetItem>().map((i) => i.id).toList(), containsAll(['term', 'tbl', 'img', 'cam', 'now', 'pos']));
    final setup = pages[1];
    expect(setup.blocks.single.items.whereType<WidgetItem>().map((i) => i.id), ['help', 'name', 'pw', 'notes']);
    expect(st.pageOf(st.widgets['pump']!), 'main');
    expect(st.pageOf(st.widgets['help']!), 'setup');
  });

  test('ui without pages gets one unnamed page', () {
    apply(vectorMsg('ui minimal'));
    expect(st.pages().single.id, '');
    expect(st.firstPage(), '');
  });

  test('duplicate ids keep the first, unknown types are kept for the placeholder', () {
    apply({'t': 'ui', 'rev': 1, 'w': [{'id': 'a', 'ty': 'label', 'lbl': 'first'}, {'id': 'a', 'ty': 'label', 'lbl': 'second'}, {'id': 'z', 'ty': 'hologram'}]});
    expect(st.widgets['a']!.lbl, 'first');
    expect(st.order, ['a', 'z']);
  });

  test('upd stores values and bumps per-widget keys', () {
    apply(vectorMsg('ui full showcase'));
    var pump = 0, temp = 0;
    st.listen('v:pump').addListener(() => pump++);
    st.listen('v:temp').addListener(() => temp++);
    apply(vectorMsg('upd mixed values'));
    expect(st.values['temp'], 21.5);
    expect(st.values['pump'], isTrue);
    expect(st.values['joy'], [10, -20]);
    expect(st.values['tbl'], [['a', 1], ['b', 2]]);
    expect(pump, 1);
    expect(temp, 1);
    apply({'t': 'upd', 'v': {'pump': false}});
    expect(pump, 2);
    expect(temp, 1, reason: 'untouched widgets are not notified');
  });

  test('prop merges in place; structural props invalidate the layout', () {
    apply(vectorMsg('ui full showcase'));
    var layout = 0, w = 0;
    st.listen('layout').addListener(() => layout++);
    st.listen('w:temp').addListener(() => w++);
    apply(vectorMsg('prop label and color'));
    expect(st.widgets['temp']!.lbl, 'Temp (HOT)');
    expect(st.widgets['temp']!.color, '#ff0000');
    expect(st.widgets['temp']!.max, 120, reason: 'other props survive');
    expect(w, 1);
    expect(layout, 0);
    apply(vectorMsg('prop hide'));
    expect(st.widgets['reset']!.vis, isFalse);
    expect(layout, 1);
    apply(vectorMsg('prop disable and range'));
    expect(st.widgets['target']!.dis, isTrue);
    expect(st.widgets['target']!.max, 150);
    apply({'t': 'prop', 'id': 'nope', 'p': {'lbl': 'x'}});
  });

  test('pts: uptime timestamps are rebased on hello, ring buffer trimmed to win', () {
    apply(vectorMsg('device hello no auth'));
    apply({'t': 'ui', 'rev': 1, 'w': [{'id': 'c', 'ty': 'chart', 'win': 10, 'series': [{'id': 'a'}, {'id': 'b'}]}]});
    apply({'t': 'pts', 'id': 'c', 's': 'a', 'p': [[123456, 1], [124456, 2]]});
    final a = st.charts['c']!['a']!;
    expect(a.first.$1, 1728700000000);
    expect(a.last.$1, 1728700001000);
    apply({'t': 'pts', 'id': 'c', 's': 'a', 'p': [[124456, 9]]});
    expect(a.length, 2, reason: 'non-increasing timestamps are dropped');
    apply({'t': 'pts', 'id': 'c', 's': 'b', 'p': [[1728700020000, 5]]});
    expect(st.charts['c']!['a'], isEmpty, reason: 'older than latest - win');
    expect(st.charts['c']!['b']!.single.$2, 5);
  });

  test('log: widget ring buffer with cap, console cap, de-dup on replay', () {
    apply({'t': 'ui', 'rev': 1, 'w': [{'id': 'term', 'ty': 'log', 'cap': 10}]});
    for (var i = 0; i < 15; i++) {
      apply({'t': 'log', 'id': 'term', 'msg': 'line $i'});
    }
    expect(st.logs['term']!.length, 10);
    expect(st.logs['term']!.first.msg, 'line 5');
    apply(vectorMsg('log to widget with color and ts'));
    apply(vectorMsg('log to widget with color and ts'));
    expect(st.logs['term']!.where((l) => l.msg == 'overheat').length, 1);
    expect(st.logs['term']!.last.c, '#ff0000');
    apply(vectorMsg('log plain'));
    expect(st.console.single.msg, 'boot ok');
  });

  test('dialogs: open, dedupe, close by id and by device', () {
    apply(vectorMsg('dlg confirm'));
    apply(vectorMsg('dlg confirm'));
    apply(vectorMsg('dlg prompt with default and timeout'));
    expect(st.dialogs.map((d) => d.id), ['d1', 'd2']);
    expect(st.dialogs[1].def, 'Boiler');
    expect(st.dialogs[1].timeout, 120);
    apply(vectorMsg('dlg close'));
    expect(st.dialogs.single.id, 'd2');
    apply({'t': 'dlg', 'id': 'd9', 'msg': 'no kind'});
    expect(st.dialogs.length, 1);
  });

  test('toasts: level normalised, capped at 5, err messages included', () {
    for (var i = 0; i < 7; i++) {
      apply({'t': 'toast', 'lvl': i.isEven ? 'info' : 'debug', 'msg': 't$i'});
    }
    expect(st.toasts.length, 5);
    expect(st.toasts.first.msg, 't2');
    expect(st.toasts.every((t) => t.lvl == 'info'), isTrue);
    st.removeToast(st.toasts.first.id);
    expect(st.toasts.length, 4);
  });

  test('sys replies land in typed slots; ota progress tracked; reset clears them', () {
    apply(vectorMsg('sys info reply'));
    expect(st.sysInfo!.chip, 'ESP32-S3');
    expect(st.sysInfo!.rr, 'power');
    apply(vectorMsg('sys wifi.status push'));
    expect(st.wifi!.st, 'connected');
    apply(vectorMsg('sys wifi.scan reply'));
    expect(st.wifiScan!.map((a) => a.ssid), ['Home', 'Cafe']);
    apply({'t': 'sys', 'cmd': 'ota.progress', 'pct': 42});
    expect(st.ota!.pct, 42);
    apply({'t': 'sys', 'cmd': 'ota.done', 'ok': false, 'msg': 'md5 mismatch'});
    expect(st.ota!.done, isTrue);
    expect(st.ota!.ok, isFalse);
    expect(st.toasts.last.msg, 'ota.done: md5 mismatch');
    st.reset();
    expect(st.sysInfo, isNull);
    expect(st.ota, isNull);
  });

  test('wallTime: epoch ms pass through, uptime rebased, no hello falls back to now', () {
    expect(st.wallTime(1728700000123).millisecondsSinceEpoch, 1728700000123);
    expect(st.wallTime(5000), now);
    apply(vectorMsg('device hello pin required with nonce'));
    expect(st.wallTime(6000), now.add(const Duration(seconds: 1)));
  });

  test('page switch keeps a valid page across ui rebuilds', () {
    apply(vectorMsg('ui full showcase'));
    st.setPage('setup');
    apply(vectorMsg('ui full showcase'));
    expect(st.page, 'setup');
    apply(vectorMsg('ui minimal'));
    expect(st.page, '');
  });
}
