import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'line_framer.dart';
import 'transport.dart';

/// An open byte link (USB serial port, Bluetooth SPP socket, in-memory pipe in tests).
abstract class ByteLink {
  Stream<Uint8List> get input;
  Future<void> write(Uint8List data);
  Future<void> close();
}

typedef ByteLinkOpener = Future<ByteLink> Function();

/// Line-framed transport over a byte link (PROTOCOL.md 2 "Stream"): one newline-free JSON per `\n` line,
/// no binary frames. Lines that are not a JSON object (boot output, log lines) are ignored.
class StreamTransport implements Transport {
  StreamTransport({required this.label, required this.opener, int maxLine = 65536}) : _framer = LineFramer(cap: maxLine);

  @override
  final String label;
  final ByteLinkOpener opener;
  final LineFramer _framer;
  ByteLink? _link;
  StreamSubscription? _sub;
  final _messages = StreamController<String>.broadcast();
  final _events = StreamController<TransportEvent>.broadcast();
  Future<void> _tx = Future.value();
  bool _isOpen = false;
  bool _closedEmitted = false;

  @override
  bool get supportsBinary => false;
  @override
  bool get isOpen => _isOpen;
  @override
  Stream<String> get messages => _messages.stream;
  @override
  Stream<TransportEvent> get events => _events.stream;

  @override
  Future<void> connect() async {
    _events.add(const TransportEvent(TransportState.connecting));
    try {
      final link = await opener();
      _link = link;
      _framer.reset();
      _sub = link.input.listen(_onBytes, onError: (Object e) => _closed(e), onDone: () => _closed('link closed'), cancelOnError: true);
      _isOpen = true;
      _events.add(const TransportEvent(TransportState.open));
    } catch (e) {
      _closed(e);
    }
  }

  void _onBytes(Uint8List data) {
    for (final ev in _framer.feed(data)) {
      if (ev is LineText && ev.text.startsWith('{') && !_messages.isClosed) _messages.add(ev.text);
    }
  }

  void _closed([Object? reason]) {
    _isOpen = false;
    if (_closedEmitted) return;
    _closedEmitted = true;
    if (!_events.isClosed) _events.add(TransportEvent(TransportState.closed, reason));
  }

  @override
  bool send(String text) {
    final link = _link;
    if (!_isOpen || link == null) return false;
    final bytes = Uint8List.fromList(utf8.encode('$text\n'));
    _tx = _tx.then((_) => link.write(bytes)).catchError((Object e) {
      _closed(e);
    });
    return true;
  }

  @override
  bool sendBinary(Uint8List data) => false;

  @override
  Future<void> close() async {
    _isOpen = false;
    await _sub?.cancel();
    _sub = null;
    try {
      await _link?.close();
    } catch (_) {}
    _link = null;
    _closed('closed by client');
    await _messages.close();
    await _events.close();
  }
}
