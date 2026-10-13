import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../features/render/ui_store.dart';
import '../proto/codec.dart';
import '../proto/hmac.dart';
import '../proto/messages.dart';
import '../transport/transport.dart';
import 'token_store.dart';

enum ConnState { connecting, pin, locked, ready, offline, stopped }

/// Actions the renderer needs from a session; widget tests use a recording fake.
abstract class UiActions {
  bool set(String id, dynamic v);
  bool ev(String id, [dynamic v]);
  bool dlg(String id, bool ok, [String? v]);
  bool page(String id);
  bool sys(String cmd, [Map<String, dynamic> extra]);
}

/// Handshake state machine (PROTOCOL.md 3): hello -> auth (PIN) -> time -> traffic, plus reconnect with backoff.
class Session extends ChangeNotifier implements UiActions {
  Session({
    required this.transportFactory,
    required this.tokens,
    required this.store,
    this.deviceId,
    this.client = 'app',
    Duration Function(int attempt)? backoff,
    this.maxBackoff = const Duration(seconds: 10),
  }) : _backoff = backoff ?? _defaultBackoff;

  final TransportFactory transportFactory;
  final TokenStore tokens;
  final UiStore store;
  final String client;
  final Duration Function(int attempt) _backoff;
  final Duration maxBackoff;

  /// Known device id (from discovery / saved list); updated from hello.
  String? deviceId;
  ConnState state = ConnState.stopped;
  int? authLeft;
  DateTime? lockUntil;
  Transport? transport;

  /// Reason of the last transport close (e.g. a PermissionDenied), cleared when a transport opens.
  Object? lastError;
  String? _nonce;
  String? _pendingPin;
  String? _sentToken;
  bool _tokenRetried = false;
  bool _stopped = true;
  int _attempt = 0;
  Timer? _retry;
  Timer? _lockTimer;
  StreamSubscription? _msgSub;
  StreamSubscription? _evSub;
  int _gen = 0;

  static Duration _defaultBackoff(int attempt) =>
      Duration(milliseconds: math.min(10000, 500 * math.pow(2, math.min(attempt, 5)).toInt()));

  String get label => transport?.label ?? '';
  bool get isOpen => transport?.isOpen ?? false;
  bool get supportsBinary => transport?.supportsBinary ?? false;

  void _setState(ConnState s, {int? left}) {
    state = s;
    authLeft = left;
    notifyListeners();
  }

  void start() {
    _stopped = false;
    _attempt = 0;
    _setState(ConnState.connecting);
    _connect();
  }

  Future<void> stop() async {
    _stopped = true;
    _retry?.cancel();
    _retry = null;
    _lockTimer?.cancel();
    _lockTimer = null;
    await _teardown();
    _setState(ConnState.stopped);
  }

  @override
  void dispose() {
    _stopped = true;
    _retry?.cancel();
    _lockTimer?.cancel();
    _teardown();
    super.dispose();
  }

  Future<void> _teardown() async {
    final t = transport;
    transport = null;
    _gen++;
    await _msgSub?.cancel();
    await _evSub?.cancel();
    _msgSub = null;
    _evSub = null;
    if (t != null) await t.close();
  }

  Future<void> _connect() async {
    if (_stopped) return;
    await _teardown();
    final gen = _gen;
    final t = transportFactory();
    transport = t;
    _msgSub = t.messages.listen((m) {
      if (gen == _gen) _onText(m);
    });
    _evSub = t.events.listen((e) {
      if (gen != _gen) return;
      if (e.state == TransportState.open) {
        lastError = null;
        _onOpen();
      }
      if (e.state == TransportState.closed) {
        lastError = e.error;
        _onClose();
      }
    });
    if (state != ConnState.locked) _setState(ConnState.connecting);
    await t.connect();
  }

  /// Reconnects now (or after [delay]); resets the backoff.
  void reconnect([Duration delay = Duration.zero]) {
    _stopped = false;
    _attempt = 0;
    _schedule(delay);
  }

  void _schedule([Duration? delay]) {
    if (_stopped || _retry != null) return;
    final d = delay ?? _backoff(_attempt++);
    _retry = Timer(d, () {
      _retry = null;
      _connect();
    });
  }

  Future<void> _onOpen() async {
    _attempt = 0;
    _tokenRetried = false;
    _nonce = null;
    final id = deviceId ?? store.device?.id;
    final tok = id != null ? await tokens.get(id) : null;
    if (transport?.isOpen != true) return;
    _sentToken = tok;
    send(C2d.hello(tok: tok, client: client));
  }

  void _onClose() {
    if (state != ConnState.locked) _setState(ConnState.offline);
    store.reset();
    _schedule();
  }

  void _onText(String text) {
    final m = decode(text);
    if (m == null) return;
    store.apply(m);
    if (m is HelloMsg) _onHello(m);
    if (m is AuthMsg) _onAuth(m);
  }

  Future<void> _onHello(HelloMsg m) async {
    deviceId = m.id;
    if (m.ok) return _authenticated();
    if (m.lock != null && m.lock! > 0) return _locked(m.lock!);
    if (_sentToken != null) {
      await tokens.remove(m.id);
      _sentToken = null;
    } else if (!_tokenRetried) {
      // The saved id may have been unknown before the first hello: retry once with its token.
      _tokenRetried = true;
      final tok = await tokens.get(m.id);
      if (tok != null && isOpen) {
        _sentToken = tok;
        send(C2d.hello(tok: tok, client: client));
        return;
      }
    }
    _nonce = m.nonce;
    final pin = _pendingPin;
    if (pin != null && _nonce != null) {
      _pendingPin = null;
      submitPin(pin);
      return;
    }
    _setState(ConnState.pin, left: authLeft);
  }

  Future<void> _onAuth(AuthMsg m) async {
    if (m.ok) {
      final id = deviceId;
      if (m.tok != null && id != null) await tokens.put(id, m.tok!);
      return _authenticated();
    }
    if (m.lock != null && m.lock! > 0) return _locked(m.lock!);
    _setState(ConnState.pin, left: m.left);
    send(C2d.hello(client: client));
  }

  void _locked(int seconds) {
    lockUntil = DateTime.now().add(Duration(seconds: seconds));
    _setState(ConnState.locked);
    _lockTimer?.cancel();
    _lockTimer = Timer(Duration(seconds: seconds, milliseconds: 500), () async {
      _lockTimer = null;
      if (_stopped) return;
      if (isOpen) {
        final id = deviceId;
        final tok = id != null ? await tokens.get(id) : null;
        _sentToken = tok;
        send(C2d.hello(tok: tok, client: client));
      } else {
        reconnect();
      }
    });
  }

  void _authenticated() {
    _setState(ConnState.ready);
    send(C2d.time());
    final first = store.firstPage();
    if (store.page.isNotEmpty && store.page != first) send(C2d.page(store.page));
  }

  /// Answers the PIN challenge; asks for a fresh nonce first when none is pending.
  void submitPin(String pin) {
    final id = deviceId;
    final nonce = _nonce;
    if (nonce == null || id == null) {
      _pendingPin = pin;
      send(C2d.hello(client: client));
      return;
    }
    _nonce = null;
    send(C2d.auth(hmacPin(pin, nonce, id)));
  }

  Future<void> forget() async {
    final id = deviceId;
    if (id != null) await tokens.remove(id);
  }

  bool send(Map<String, dynamic> msg) => transport?.send(encode(msg)) ?? false;
  bool sendBinary(Uint8List data) => transport?.sendBinary(data) ?? false;

  @override
  bool set(String id, dynamic v) {
    store.setLocal(id, v);
    return send(C2d.set(id, v));
  }

  @override
  bool ev(String id, [dynamic v]) => send(C2d.ev(id, v));

  @override
  bool dlg(String id, bool ok, [String? v]) {
    store.closeDialog(id);
    return send(C2d.dlg(id, ok, v));
  }

  @override
  bool page(String id) {
    store.setPage(id);
    return send(C2d.page(id));
  }

  @override
  bool sys(String cmd, [Map<String, dynamic> extra = const {}]) => send(C2d.sys(cmd, extra));
}
