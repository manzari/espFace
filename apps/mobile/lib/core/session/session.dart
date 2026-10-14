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

const backoffBase = Duration(milliseconds: 500);
const backoffCap = Duration(seconds: 30);

/// 500 ms * 2^attempt capped at 30 s, with +-25 % jitter so many clients do not retry in lockstep.
Duration backoffDelay(int attempt, {math.Random? rng}) {
  final exp = math.min(backoffCap.inMilliseconds, backoffBase.inMilliseconds * math.pow(2, math.min(attempt, 10)).toInt());
  final r = (rng ?? _rng).nextDouble();
  return Duration(milliseconds: math.min(backoffCap.inMilliseconds, (exp * (0.75 + r * 0.5)).round()));
}

final _rng = math.Random();

/// Actions the renderer needs from a session; widget tests use a recording fake.
abstract class UiActions {
  bool set(String id, dynamic v);
  bool ev(String id, [dynamic v]);
  bool dlg(String id, bool ok, [String? v]);
  bool page(String id);
  bool sys(String cmd, [Map<String, dynamic> extra]);
}

/// Handshake state machine (PROTOCOL.md 3): hello -> auth (PIN) -> time -> traffic, plus reconnect with backoff.
/// The UI model in [store] survives disconnects (last known state stays visible); only per-connection state is reset.
class Session extends ChangeNotifier implements UiActions {
  Session({
    required this.transportFactory,
    required this.tokens,
    required this.store,
    this.deviceId,
    this.client = 'app',
    Duration Function(int attempt)? backoff,
  }) : _backoff = backoff ?? backoffDelay;

  final TransportFactory transportFactory;
  final TokenStore tokens;
  final UiStore store;
  final String client;
  final Duration Function(int attempt) _backoff;

  /// Known device id (from discovery / saved list); updated from hello.
  String? deviceId;
  ConnState state = ConnState.stopped;
  int? authLeft;
  DateTime? lockUntil;
  Transport? transport;

  /// The device refused the last hello with err 9 (too many clients); retried with backoff.
  bool busy = false;

  /// When the next automatic reconnect fires (null when none is pending).
  DateTime? retryAt;

  /// Reconnect attempts since [start] (for tests and the connection page).
  int attempts = 0;

  /// Reason of the last transport close (e.g. a PermissionDenied), cleared when a transport opens.
  Object? lastError;
  String? _nonce;
  String? _pendingPin;
  String? _lastPin;
  bool _pinRetried = false;
  String? _sentToken;
  bool _tokenRetried = false;
  bool _stopped = true;
  bool _background = false;
  bool _disposed = false;
  int _attempt = 0;
  Timer? _retry;
  Timer? _lockTimer;
  StreamSubscription? _msgSub;
  StreamSubscription? _evSub;
  int _gen = 0;

  String get label => transport?.label ?? '';
  bool get isOpen => transport?.isOpen ?? false;
  bool get supportsBinary => transport?.supportsBinary ?? false;
  bool get inBackground => _background;

  void _setState(ConnState s, {int? left}) {
    state = s;
    authLeft = left;
    if (!_disposed) notifyListeners();
  }

  void start() {
    _stopped = false;
    _attempt = 0;
    attempts = 0;
    _setState(ConnState.connecting);
    _connect();
  }

  Future<void> stop() async {
    _stopped = true;
    _cancelRetry();
    _lockTimer?.cancel();
    _lockTimer = null;
    await _teardown();
    _setState(ConnState.stopped);
  }

  @override
  void dispose() {
    _stopped = true;
    _disposed = true;
    _cancelRetry();
    _lockTimer?.cancel();
    _lockTimer = null;
    _teardown();
    super.dispose();
  }

  void _cancelRetry() {
    _retry?.cancel();
    _retry = null;
    retryAt = null;
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
    if (_stopped) return;
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

  /// Reconnects now (or after [delay]) and resets the backoff; replaces any pending automatic retry.
  void reconnect([Duration delay = Duration.zero]) {
    _stopped = false;
    _attempt = 0;
    _cancelRetry();
    _schedule(delay);
  }

  /// In the background no reconnects are attempted; coming back reconnects at once when the link is gone.
  void setBackground(bool background) {
    if (_background == background) return;
    _background = background;
    if (background) {
      _cancelRetry();
    } else if (!_stopped && !isOpen) {
      reconnect();
    }
  }

  void _schedule([Duration? delay]) {
    if (_stopped || _background || _retry != null) return;
    final d = delay ?? _backoff(_attempt++);
    attempts++;
    retryAt = DateTime.now().add(d);
    _retry = Timer(d, () {
      _retry = null;
      retryAt = null;
      _connect();
    });
    if (!_disposed) notifyListeners();
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
    if (m is ErrMsg) _onErr(m);
  }

  Future<void> _onHello(HelloMsg m) async {
    deviceId = m.id;
    busy = false;
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
    _lastPin = null;
    _setState(ConnState.pin, left: m.left);
    send(C2d.hello(client: client));
  }

  // err 9 on hello: the device is full, keep retrying with backoff. err 5 on auth without an auth reply
  // (flaky device): retry the same PIN once with a fresh nonce, then ask the user again.
  void _onErr(ErrMsg m) {
    if (m.code == 9 && m.ref == 'hello') {
      busy = true;
      if (!_disposed) notifyListeners();
      return;
    }
    if (m.ref != 'auth' || state == ConnState.ready) return;
    final pin = _lastPin;
    if (pin != null && !_pinRetried) {
      _pinRetried = true;
      _pendingPin = pin;
      send(C2d.hello(client: client));
      return;
    }
    _lastPin = null;
    _setState(ConnState.pin, left: authLeft);
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
    _lastPin = null;
    _pinRetried = false;
    _setState(ConnState.ready);
    send(C2d.time());
    final first = store.firstPage();
    if (store.page.isNotEmpty && store.page != first) send(C2d.page(store.page));
  }

  /// Answers the PIN challenge; asks for a fresh nonce first when none is pending.
  void submitPin(String pin) {
    final id = deviceId;
    final nonce = _nonce;
    _lastPin = pin;
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
