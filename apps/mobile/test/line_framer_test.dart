import 'dart:convert';

import 'package:espface/core/transport/line_framer.dart';
import 'package:flutter_test/flutter_test.dart';

List<Object> flat(List<LineEvent> evs) => [for (final e in evs) e is LineText ? e.text : 'OVERSIZE'];

void main() {
  test('a line split over several feeds', () {
    final f = LineFramer();
    expect(f.feed(utf8.encode('{"t":"he')), isEmpty);
    expect(f.feed(utf8.encode('llo"}')), isEmpty);
    expect(flat(f.feed(utf8.encode('\n'))), ['{"t":"hello"}']);
  });

  test('several lines in one feed, partial tail kept', () {
    final f = LineFramer();
    expect(flat(f.feed(utf8.encode('{"a":1}\n{"b":2}\n{"c"'))), ['{"a":1}', '{"b":2}']);
    expect(flat(f.feed(utf8.encode(':3}\n'))), ['{"c":3}']);
  });

  test('CR is dropped and empty lines are skipped', () {
    final f = LineFramer();
    expect(flat(f.feed(utf8.encode('\r\n\n{"a":1}\r\n\r\n'))), ['{"a":1}']);
  });

  test('oversize line reported once at its newline, next line fine', () {
    final f = LineFramer(cap: 8);
    final evs = [...f.feed(utf8.encode('123456789abc')), ...f.feed(utf8.encode('def\n{"ok":1}\n'))];
    expect(flat(evs), ['OVERSIZE', '{"ok":1}']);
    expect(flat(f.feed(utf8.encode('12345678\n'))), ['12345678']);
  });

  test('utf-8 and reset', () {
    final f = LineFramer();
    expect(flat(f.feed(utf8.encode('{"s":"Grüße ✓"}\n'))), ['{"s":"Grüße ✓"}']);
    f.feed(utf8.encode('partial'));
    f.reset();
    expect(flat(f.feed(utf8.encode('x\n'))), ['x']);
  });
}
