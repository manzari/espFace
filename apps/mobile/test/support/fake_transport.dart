import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:espface/core/session/session.dart';
import 'package:espface/core/transport/transport.dart';

/// Scriptable transport: tests push device frames with [receive] and inspect [sent] / [binary].
class FakeTransport implements Transport {
  FakeTransport({this.autoOpen = true});
  final bool autoOpen;
  final sent = <Map<String, dynamic>>[];
  final binary = <Uint8List>[];
  final _messages = StreamController<String>.broadcast();
  final _events = StreamController<TransportEvent>.broadcast();
  bool _open = false;
  bool closed = false;

  @override
  String get label => 'fake://device';
  @override
  bool get supportsBinary => true;
  @override
  bool get isOpen => _open;
  @override
  Stream<String> get messages => _messages.stream;
  @override
  Stream<TransportEvent> get events => _events.stream;

  @override
  Future<void> connect() async {
    _events.add(const TransportEvent(TransportState.connecting));
    if (autoOpen) open();
  }

  void open() {
    _open = true;
    _events.add(const TransportEvent(TransportState.open));
  }

  void drop() {
    _open = false;
    _events.add(const TransportEvent(TransportState.closed));
  }

  void receive(Map<String, dynamic> msg) => _messages.add(jsonEncode(msg));
  void receiveRaw(String text) => _messages.add(text);

  @override
  bool send(String text) {
    if (!_open) return false;
    sent.add(Map<String, dynamic>.from(jsonDecode(text) as Map));
    return true;
  }

  @override
  bool sendBinary(Uint8List data) {
    if (!_open) return false;
    binary.add(data);
    return true;
  }

  @override
  Future<void> close() async {
    _open = false;
    closed = true;
    await _messages.close();
    await _events.close();
  }

  Map<String, dynamic>? last([String? t]) {
    for (final m in sent.reversed) {
      if (t == null || m['t'] == t) return m;
    }
    return null;
  }

  List<Map<String, dynamic>> ofType(String t) => sent.where((m) => m['t'] == t).toList();
}

/// Records renderer actions for widget tests.
class RecordingActions implements UiActions {
  final calls = <(String, List<dynamic>)>[];
  @override
  bool set(String id, dynamic v) {
    calls.add(('set', [id, v]));
    return true;
  }

  @override
  bool ev(String id, [dynamic v]) {
    calls.add(('ev', [id, v]));
    return true;
  }

  @override
  bool dlg(String id, bool ok, [String? v]) {
    calls.add(('dlg', [id, ok, v]));
    return true;
  }

  @override
  bool page(String id) {
    calls.add(('page', [id]));
    return true;
  }

  @override
  bool sys(String cmd, [Map<String, dynamic> extra = const {}]) {
    calls.add(('sys', [cmd, extra]));
    return true;
  }

  List<dynamic>? last(String kind) {
    for (final c in calls.reversed) {
      if (c.$1 == kind) return c.$2;
    }
    return null;
  }
}

/// Lets async stream events settle in plain (non-widget) tests.
Future<void> settle([int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
