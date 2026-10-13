import 'dart:async';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'transport.dart';

/// WebSocket transport: `ws://<host>[:port]/ws`. Text frames are protocol messages, binary frames OTA data.
class WsTransport implements Transport {
  WsTransport(this.url, {this.connectTimeout = const Duration(seconds: 8)});

  /// Builds the URL from a user supplied `host[:port]` (scheme and path optional).
  factory WsTransport.host(String host) => WsTransport(urlForHost(host));

  static Uri urlForHost(String host) {
    var h = host.trim();
    if (h.startsWith('ws://') || h.startsWith('wss://')) {
      final u = Uri.parse(h);
      return u.path.isEmpty || u.path == '/' ? u.replace(path: '/ws') : u;
    }
    if (h.startsWith('http://')) h = h.substring(7);
    if (h.startsWith('https://')) h = h.substring(8);
    h = h.split('/').first;
    return Uri.parse('ws://$h/ws');
  }

  final Uri url;
  final Duration connectTimeout;
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  final _messages = StreamController<String>.broadcast();
  final _events = StreamController<TransportEvent>.broadcast();
  bool _open = false;
  bool _closedEmitted = false;

  @override
  String get label => url.toString();
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
    try {
      final ch = WebSocketChannel.connect(url);
      _ch = ch;
      await ch.ready.timeout(connectTimeout);
      _open = true;
      _sub = ch.stream.listen(
        (data) {
          if (data is String) _messages.add(data);
        },
        onError: (Object e) => _closed(e),
        onDone: () => _closed(ch.closeReason),
        cancelOnError: true,
      );
      _events.add(const TransportEvent(TransportState.open));
    } catch (e) {
      _closed(e);
    }
  }

  void _closed([Object? reason]) {
    _open = false;
    if (_closedEmitted) return;
    _closedEmitted = true;
    if (!_events.isClosed) _events.add(TransportEvent(TransportState.closed, reason));
  }

  @override
  bool send(String text) {
    if (!_open || _ch == null) return false;
    _ch!.sink.add(text);
    return true;
  }

  @override
  bool sendBinary(Uint8List data) {
    if (!_open || _ch == null) return false;
    _ch!.sink.add(data);
    return true;
  }

  @override
  Future<void> close() async {
    _open = false;
    await _sub?.cancel();
    _sub = null;
    try {
      await _ch?.sink.close();
    } catch (_) {}
    _ch = null;
    _closed('closed by client');
    await _messages.close();
    await _events.close();
  }
}
