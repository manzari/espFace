import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'ble_framer.dart';
import 'ble_gatt.dart';
import 'transport.dart';

/// BLE transport (PROTOCOL.md 2): connect by platform device id, subscribe TX, negotiate MTU 512, write RX in
/// `[seq][flags][payload]` packets sized by the live MTU, reassemble notifications into text messages.
/// No binary frames (OTA push unavailable). Reconnects are driven by the session like any other transport.
class BleTransport implements Transport, ChunkedTransport {
  BleTransport(this.id, {this.gatt = const FbpGatt(), this.connectTimeout = const Duration(seconds: 20), int maxMessage = 65536}) : _rx = BleReassembler(cap: maxMessage);

  final String id;
  final Duration connectTimeout;
  final BleGatt gatt;
  final BleChunker _tx = BleChunker();
  final BleReassembler _rx;
  BleChannel? _ch;
  final List<StreamSubscription> _subs = [];
  final _messages = StreamController<String>.broadcast();
  final _events = StreamController<TransportEvent>.broadcast();
  final ValueNotifier<bool> _receiving = ValueNotifier(false);
  Future<void> _txQueue = Future.value();
  bool _isOpen = false;
  bool _closedEmitted = false;

  @override
  String get label => 'ble://$id';
  @override
  bool get supportsBinary => false;
  @override
  bool get isOpen => _isOpen;
  @override
  Stream<String> get messages => _messages.stream;
  @override
  Stream<TransportEvent> get events => _events.stream;
  @override
  ValueListenable<bool> get receiving => _receiving;

  /// Payload bytes per packet at the current MTU.
  int get payloadMax => _tx.payloadMax;

  @override
  Future<void> connect() async {
    _events.add(const TransportEvent(TransportState.connecting));
    try {
      final ch = await gatt.open(id, timeout: connectTimeout, mtu: bleMaxMtu);
      _ch = ch;
      _tx.reset();
      _tx.setMtu(ch.mtu);
      _rx.reset();
      _subs.add(ch.notifications.listen(_onPacket, onError: (Object e) => _closed(e)));
      _subs.add(ch.mtuChanges.listen(_tx.setMtu));
      _subs.add(ch.disconnected.listen((reason) => _closed(reason ?? 'disconnected')));
      _isOpen = true;
      _events.add(const TransportEvent(TransportState.open));
    } catch (e) {
      _closed(e);
    }
  }

  void _onPacket(List<int> pkt) {
    final r = _rx.feed(pkt);
    _receiving.value = _rx.partial;
    if (r == BleFeed.message && !_messages.isClosed) _messages.add(utf8.decode(_rx.message!, allowMalformed: true));
  }

  void _closed([Object? reason]) {
    _isOpen = false;
    _receiving.value = false;
    if (_closedEmitted) return;
    _closedEmitted = true;
    if (!_events.isClosed) _events.add(TransportEvent(TransportState.closed, reason));
  }

  @override
  bool send(String text) {
    final ch = _ch;
    if (!_isOpen || ch == null) return false;
    final packets = _tx.chunk(utf8.encode(text));
    _txQueue = _txQueue.then((_) async {
      for (final p in packets) {
        if (!_isOpen) return;
        await ch.write(p, withoutResponse: ch.writeWithoutResponse);
      }
    }).catchError((Object e) {
      _closed(e);
    });
    return true;
  }

  @override
  bool sendBinary(Uint8List data) => false;

  @override
  Future<void> close() async {
    _isOpen = false;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    try {
      await _ch?.close();
    } catch (_) {}
    _ch = null;
    _closed('closed by client');
    await _messages.close();
    await _events.close();
  }
}
