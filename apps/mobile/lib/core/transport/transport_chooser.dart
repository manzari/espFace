import 'dart:async';

import 'package:flutter/foundation.dart';

import 'transport.dart';

/// Picks the medium for each connection attempt (PLAN 6.2): [kinds] in preference order (WiFi, BLE, serial,
/// or just the pinned one). A kind that fails to open is rotated out for the next attempt; a kind that opened
/// and later dropped is retried first. Exposes the active kind and the BLE "receiving" flag for the UI.
class TransportChooser {
  TransportChooser({required List<TransportKind> kinds, required this.make}) : _kinds = List.of(kinds);

  final Transport Function(TransportKind kind) make;
  List<TransportKind> _kinds;
  int _i = 0;
  final ValueNotifier<TransportKind?> active = ValueNotifier(null);
  final ValueNotifier<bool> receiving = ValueNotifier(false);

  List<TransportKind> get kinds => List.unmodifiable(_kinds);

  /// Returns true when the list changed (the caller then reconnects).
  bool setKinds(List<TransportKind> kinds) {
    if (listEquals(kinds, _kinds)) return false;
    _kinds = List.of(kinds);
    _i = 0;
    return true;
  }

  TransportKind? get next => _kinds.isEmpty ? null : _kinds[_i % _kinds.length];

  Transport create() {
    final kind = next;
    if (kind == null) throw StateError('device has no transport configured');
    final t = make(kind);
    active.value = kind;
    var opened = false;
    VoidCallback? fwd;
    if (t is ChunkedTransport) {
      final r = (t as ChunkedTransport).receiving;
      fwd = () => _disposed ? null : receiving.value = r.value;
      r.addListener(fwd);
    }
    late StreamSubscription sub;
    sub = t.events.listen((e) {
      if (e.state == TransportState.open) opened = true;
      if (e.state == TransportState.closed) {
        if (!opened && _kinds.length > 1) _i = (_i + 1) % _kinds.length;
        if (fwd != null) (t as ChunkedTransport).receiving.removeListener(fwd);
        if (!_disposed) receiving.value = false;
        sub.cancel();
      }
    });
    return t;
  }

  bool _disposed = false;

  /// Close events of the last transport may still arrive afterwards, so the notifiers are only frozen.
  void dispose() => _disposed = true;
}
