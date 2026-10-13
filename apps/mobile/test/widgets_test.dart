import 'package:espface/features/render/layout.dart';
import 'package:espface/features/render/widgets/basic.dart';
import 'package:espface/features/render/widgets/inputs.dart';
import 'package:espface/features/render/widgets/media.dart';
import 'package:espface/features/render/widgets/registry.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump.dart';

void main() {
  test('registry covers every protocol widget type', () {
    const types = ['label', 'button', 'switch', 'slider', 'number', 'text', 'textarea', 'select', 'flags', 'color', 'datetime', 'joystick', 'dpad', 'gauge', 'progress', 'display', 'led', 'chart', 'log', 'table', 'image', 'stream', 'clock', 'map', 'textblock', 'header', 'group', 'page', 'row', 'spacer'];
    expect(widgetRegistry.keys.toSet(), types.toSet());
  });

  testWidgets('label formats value and unit', (t) async {
    await pumpWidgetDef(t, {'id': 'temp', 'ty': 'label', 'lbl': 'Temp', 'unit': '°C', 'fmt': '%.1f'}, value: 21.46);
    expect(find.text('Temp'), findsOneWidget);
    expect(find.textContaining('21.5'), findsOneWidget);
  });

  testWidgets('button sends ev; hold button sends press and release', (t) async {
    final h = await pumpWidgetDef(t, {'id': 'reset', 'ty': 'button', 'lbl': 'Reset', 'icon': 'restart_alt'});
    await t.tap(find.text('Reset'));
    expect(h.actions.last('ev'), ['reset', null]);

    final h2 = await pumpWidgetDef(t, {'id': 'horn', 'ty': 'button', 'lbl': 'Horn', 'hold': true, 'color': '#ff0000'});
    final g = await t.startGesture(t.getCenter(find.text('Horn')));
    await t.pump();
    expect(h2.actions.last('ev'), ['horn', 1]);
    await g.up();
    await t.pump();
    expect(h2.actions.last('ev'), ['horn', 0]);
  });

  testWidgets('switch sets bool and shows state label; ro disables', (t) async {
    final h = await pumpWidgetDef(t, {'id': 'pump', 'ty': 'switch', 'lbl': 'Pump', 'on': 'ON', 'off': 'OFF'}, value: false);
    expect(find.text('OFF'), findsOneWidget);
    await t.tap(find.byType(Switch));
    expect(h.actions.last('set'), ['pump', true]);
    h.upd('pump', true);
    await t.pump();
    expect(find.text('ON'), findsOneWidget);

    await pumpWidgetDef(t, {'id': 'x', 'ty': 'switch', 'lbl': 'X', 'ro': true}, value: true);
    expect(t.widget<Switch>(find.byType(Switch)).onChanged, isNull);
  });

  testWidgets('slider sends rounded value after drag', (t) async {
    final h = await pumpWidgetDef(t, {'id': 'target', 'ty': 'slider', 'lbl': 'Target', 'min': 20, 'max': 90, 'step': 1, 'unit': '°C'}, value: 60);
    expect(find.text('60 °C'), findsOneWidget);
    await t.drag(find.byType(Slider), const Offset(80, 0));
    await t.pump(const Duration(milliseconds: 200));
    final v = h.actions.last('set')!;
    expect(v[0], 'target');
    expect(v[1], isA<int>());
    expect(v[1] as int, greaterThan(60));
  });

  testWidgets('number spin buttons and typed input', (t) async {
    final h = await pumpWidgetDef(t, {'id': 'n', 'ty': 'number', 'lbl': 'Cycles', 'min': 0, 'max': 10, 'step': 1, 'spin': true}, value: 3);
    await t.tap(find.byIcon(Icons.add));
    expect(h.actions.last('set'), ['n', 4]);
    await t.tap(find.byIcon(Icons.remove));
    expect(h.actions.last('set'), ['n', 2]);
    await t.enterText(find.byType(TextField), '42');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(h.actions.last('set'), ['n', 10], reason: 'clamped to max');
  });

  testWidgets('text commits on submit, validates regex, secret toggles', (t) async {
    final h = await pumpWidgetDef(t, {'id': 'name', 'ty': 'text', 'lbl': 'Name', 'maxlen': 32, 're': r'^[A-Za-z ]*$'}, value: 'Boiler');
    await t.enterText(find.byType(TextField), 'Kitchen 1');
    await t.pump();
    expect(find.textContaining('Does not match'), findsOneWidget);
    await t.testTextInput.receiveAction(TextInputAction.done);
    expect(h.actions.last('set'), isNull);
    await t.enterText(find.byType(TextField), 'Kitchen');
    await t.testTextInput.receiveAction(TextInputAction.done);
    expect(h.actions.last('set'), ['name', 'Kitchen']);

    await pumpWidgetDef(t, {'id': 'pw', 'ty': 'text', 'lbl': 'Password', 'secret': true}, value: 'x');
    expect(t.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
    await t.tap(find.byIcon(Icons.visibility));
    await t.pump();
    expect(t.widget<TextField>(find.byType(TextField)).obscureText, isFalse);
  });

  testWidgets('textarea is multiline with rows', (t) async {
    await pumpWidgetDef(t, {'id': 'notes', 'ty': 'textarea', 'lbl': 'Notes', 'rows': 4, 'maxlen': 512}, value: 'a\nb');
    expect(t.widget<TextField>(find.byType(TextField)).maxLines, 4);
  });

  testWidgets('select segmented and dropdown', (t) async {
    final h = await pumpWidgetDef(t, {'id': 'mode', 'ty': 'select', 'lbl': 'Mode', 'opts': ['Off', 'Auto', 'Manual'], 'style': 'seg'}, value: 1);
    await t.tap(find.text('Manual'));
    expect(h.actions.last('set'), ['mode', 2]);
    await pumpWidgetDef(t, {'id': 'mode', 'ty': 'select', 'lbl': 'Mode', 'opts': ['Off', 'Auto']}, value: 1);
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
  });

  testWidgets('flags toggle bits', (t) async {
    final h = await pumpWidgetDef(t, {'id': 'days', 'ty': 'flags', 'lbl': 'Days', 'opts': ['Mo', 'Tu', 'We']}, value: 1);
    await t.tap(find.text('Tu'));
    expect(h.actions.last('set'), ['days', 3]);
    await t.tap(find.text('Mo'));
    expect(h.actions.last('set'), ['days', 0]);
  });

  testWidgets('color shows hex and picker dialog sets int', (t) async {
    final h = await pumpWidgetDef(t, {'id': 'col', 'ty': 'color', 'lbl': 'Light'}, value: 0xff8800);
    expect(find.text('#ff8800'), findsOneWidget);
    await t.tap(find.byType(InkWell).first);
    await t.pumpAndSettle();
    expect(find.byType(ColorPickerDialog), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(h.actions.last('set'), ['col', 0xff8800]);
  });

  testWidgets('datetime formats and opens a picker', (t) async {
    expect(DatetimeWidget.format('time', 6 * 3600 + 5 * 60), '06:05');
    await pumpWidgetDef(t, {'id': 'start', 'ty': 'datetime', 'lbl': 'Start', 'mode': 'time'}, value: 6 * 3600);
    expect(find.text('06:00'), findsOneWidget);
    await t.tap(find.text('06:00'));
    await t.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
  });

  testWidgets('joystick sends position and auto-centers', (t) async {
    final h = await pumpWidgetDef(t, {'id': 'joy', 'ty': 'joystick', 'lbl': 'Valve', 'center': true}, value: [0, 0]);
    final pad = find.byKey(const ValueKey('joy:joy'));
    final rect = t.getRect(pad);
    final g = await t.startGesture(Offset(rect.right - 1, rect.center.dy));
    await t.pump();
    final v = h.actions.last('set')!;
    expect(v[0], 'joy');
    expect((v[1] as List)[0], greaterThan(90));
    await g.up();
    await t.pump();
    expect(h.actions.last('set'), ['joy', [0, 0]]);
  });

  testWidgets('dpad sends direction then release', (t) async {
    final h = await pumpWidgetDef(t, {'id': 'pad', 'ty': 'dpad', 'lbl': 'Move'});
    final g = await t.startGesture(t.getCenter(find.byIcon(Icons.keyboard_arrow_up)));
    await t.pump();
    expect(h.actions.last('ev'), ['pad', 'u']);
    await g.up();
    await t.pump();
    expect(h.actions.last('ev'), ['pad', 0]);
  });

  testWidgets('gauge arc, round and linear render the value', (t) async {
    for (final style in ['arc', 'round', 'linear']) {
      await pumpWidgetDef(t, {'id': 'g', 'ty': 'gauge', 'lbl': 'T', 'min': 0, 'max': 120, 'unit': '°C', 'style': style, 'zones': [{'from': 90, 'to': 120, 'color': '#ff0000'}]}, value: 95.5);
      expect(find.textContaining('95.5'), findsOneWidget, reason: style);
    }
  });

  testWidgets('progress plain and bipolar', (t) async {
    await pumpWidgetDef(t, {'id': 'level', 'ty': 'progress', 'lbl': 'Tank', 'min': 0, 'max': 100}, value: 70);
    expect(find.text('70'), findsOneWidget);
    await pumpWidgetDef(t, {'id': 'bal', 'ty': 'progress', 'lbl': 'Balance', 'min': -100, 'max': 100, 'center': true}, value: -40);
    expect(find.text('-40'), findsOneWidget);
  });

  testWidgets('display pads digits', (t) async {
    expect(DisplayWidget.format(1.85, 5), ' 1.850');
    expect(DisplayWidget.format(42, 4), '  42');
    expect(DisplayWidget.format('abcdefg', 4), 'abcd');
    await pumpWidgetDef(t, {'id': 'disp', 'ty': 'display', 'lbl': 'Pressure', 'digits': 5, 'unit': 'bar'}, value: 1.85);
    expect(find.text(' 1.850'), findsOneWidget);
    expect(find.text('bar'), findsOneWidget);
  });

  testWidgets('led bool and rgb', (t) async {
    await pumpWidgetDef(t, {'id': 'ok', 'ty': 'led', 'lbl': 'OK', 'color': '#00ff00'}, value: true);
    expect(find.text('OK'), findsOneWidget);
    await pumpWidgetDef(t, {'id': 'rgb', 'ty': 'led', 'lbl': 'Status', 'rgb': true}, value: 0x0000ff);
    expect(find.text('Status'), findsOneWidget);
  });

  testWidgets('chart waits for data then draws series with legend values', (t) async {
    final h = await pumpWidgetDef(t, {'id': 'c', 'ty': 'chart', 'lbl': 'Temp', 'series': [{'id': 'a', 'lbl': 'A', 'color': '#ff8800'}, {'id': 'b'}], 'win': 60, 'unit': '°C', 'vals': true});
    expect(find.text('waiting for data'), findsOneWidget);
    h.apply({'t': 'pts', 'id': 'c', 's': 'a', 'p': [[1728700000000, 21.5], [1728700001000, 22]]});
    await t.pump();
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('22°C'), findsAtLeastNWidgets(1));
    await t.tap(find.text('hide'));
    await t.pump();
    expect(find.text('A'), findsNothing);
    for (final style in ['area', 'bar']) {
      final h2 = await pumpWidgetDef(t, {'id': 'c', 'ty': 'chart', 'series': [{'id': 'a'}], 'style': style});
      h2.apply({'t': 'pts', 'id': 'c', 's': 'a', 'p': [[1728700000000, 1], [1728700001000, 2]]});
      await t.pump();
      expect(find.byType(style == 'bar' ? BarChart : LineChart), findsOneWidget, reason: style);
    }
  });

  testWidgets('log shows pushed lines', (t) async {
    final h = await pumpWidgetDef(t, {'id': 'term', 'ty': 'log', 'lbl': 'Log', 'rows': 4});
    h.apply({'t': 'log', 'id': 'term', 'msg': 'boot ok', 'c': '#ff0000'});
    h.apply({'t': 'log', 'id': 'term', 'msg': 'second'});
    await t.pump();
    expect(find.textContaining('boot ok'), findsOneWidget);
    expect(find.textContaining('second'), findsOneWidget);
  });

  testWidgets('table renders header and cells', (t) async {
    await pumpWidgetDef(t, {'id': 'tbl', 'ty': 'table', 'lbl': 'Zones', 'cols': [{'lbl': 'Zone', 'w': 2}, {'lbl': '°C', 'w': 1, 'align': 'right'}]}, value: [['Kitchen', 21.5], ['Bath', 23]]);
    expect(find.text('Zone'), findsOneWidget);
    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.text('23'), findsOneWidget);
  });

  testWidgets('image and stream without source', (t) async {
    await pumpWidgetDef(t, {'id': 'img', 'ty': 'image', 'lbl': 'Diagram'});
    expect(find.text('no source'), findsOneWidget);
    await pumpWidgetDef(t, {'id': 'cam', 'ty': 'stream', 'lbl': 'Camera'});
    expect(find.text('no source'), findsOneWidget);
    await pumpWidgetDef(t, {'id': 'img', 'ty': 'image', 'lbl': 'Diagram', 'src': 'http://127.0.0.1:1/x.png'});
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byType(ImageWidget), findsOneWidget);
    await unmount(t);
  });

  testWidgets('clock ticks locally from the pushed value', (t) async {
    await pumpWidgetDef(t, {'id': 'now', 'ty': 'clock', 'lbl': 'Time', 'fmt': 'HH:mm'}, value: 1728700000);
    expect(find.textContaining(RegExp(r'^\d\d:\d\d$')), findsOneWidget);
    await unmount(t);
  });

  testWidgets('map renders markers from points', (t) async {
    final pts = MapWidget.pointsOf([[52.52, 13.405, 'Boiler'], ['bad'], [1]]);
    expect(pts.length, 1);
    expect(pts.single.$2, 'Boiler');
    await pumpWidgetDef(t, {'id': 'pos', 'ty': 'map', 'lbl': 'Location', 'zoom': 14}, value: [[52.52, 13.405, 'Boiler']]);
    await t.pump();
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('Boiler'), findsOneWidget);
    await unmount(t);
  });

  testWidgets('textblock, header, spacer, unsupported', (t) async {
    await pumpWidgetDef(t, {'id': 'help', 'ty': 'textblock', 'text': 'Set the target.\nSecond line'});
    expect(find.textContaining('Second line'), findsOneWidget);
    await pumpWidgetDef(t, {'id': 'hdr', 'ty': 'header', 'lbl': 'Boiler', 'icon': 'home'});
    expect(find.text('Boiler'), findsOneWidget);
    expect(find.byIcon(Icons.home), findsOneWidget);
    await pumpWidgetDef(t, {'id': 'sp', 'ty': 'spacer', 'size': [1, 40]});
    expect(t.getSize(find.byType(SizedBox).first).height, 40);
    await pumpWidgetDef(t, {'id': 'z', 'ty': 'hologram', 'lbl': 'future'});
    expect(find.text('unsupported widget "hologram" (future)'), findsOneWidget);
  });

  testWidgets('prop updates re-render the widget; vis false hides it; dis greys out', (t) async {
    final h = await pumpWidgetDef(t, {'id': 'temp', 'ty': 'label', 'lbl': 'Temp'}, value: 1);
    h.apply({'t': 'prop', 'id': 'temp', 'p': {'lbl': 'Temp (HOT)'}});
    await t.pump();
    expect(find.text('Temp (HOT)'), findsOneWidget);
    h.apply({'t': 'prop', 'id': 'temp', 'p': {'vis': false}});
    await t.pump();
    expect(find.text('Temp (HOT)'), findsNothing);
    h.apply({'t': 'prop', 'id': 'temp', 'p': {'vis': true, 'dis': true}});
    await t.pump();
    expect(find.byType(Opacity), findsOneWidget);
  });

  testWidgets('hint shows on long press', (t) async {
    await pumpWidgetDef(t, {'id': 'reset', 'ty': 'button', 'lbl': 'Reset', 'hint': 'Clears the error latch'});
    await t.longPress(find.text('Reset'));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Clears the error latch'), findsOneWidget);
    await t.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('layout: group folds, rows lay widgets side by side', (t) async {
    final h = await pumpWidgetDef(t, {'id': 'pump', 'ty': 'switch', 'lbl': 'Pump', 'row': 'r1', 'size': 1, 'grp': 'g'}, extra: [
      {'id': 'g', 'ty': 'group', 'lbl': 'Control', 'fold': true},
      {'id': 'r1', 'ty': 'row', 'grp': 'g'},
      {'id': 'target', 'ty': 'slider', 'lbl': 'Target', 'row': 'r1', 'size': 3, 'grp': 'g'},
    ]);
    final page = h.store.pages().single;
    await t.pumpWidget(scoped(h.store, h.actions, SizedBox(height: 600, child: PageBody(page: page))));
    await t.pump();
    expect(find.text('Control'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(t.getRect(find.byType(Switch)).left, greaterThan(t.getRect(find.byType(Slider)).right), reason: 'declaration order: slider then switch');
    expect(t.getSize(find.byType(Slider)).width, greaterThan(400), reason: 'size 3 of 4');
    await t.tap(find.text('Control'));
    await t.pump();
    expect(find.byType(Switch), findsNothing);
  });
}
