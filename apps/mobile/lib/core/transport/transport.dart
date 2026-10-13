import 'package:flutter/foundation.dart';

enum TransportState { connecting, open, closed }

/// The media a saved device can be reached over, in fallback order (PLAN 6.2).
enum TransportKind {
  wifi('WiFi'),
  ble('BLE'),
  usb('USB'),
  bt('Bluetooth');

  const TransportKind(this.label);
  final String label;

  static TransportKind? parse(String? s) => s == null ? null : values.where((k) => k.name == s).firstOrNull;
}

/// One connection to a device: text messages in both directions, binary frames for OTA.
/// WsTransport, BleTransport and StreamTransport (USB, Bluetooth Classic) implement the same
/// contract so the session never knows the medium.
abstract class Transport {
  /// Human readable endpoint, e.g. `ws://192.168.4.1/ws`.
  String get label;

  /// Whether binary frames (OTA push) are supported on this medium.
  bool get supportsBinary;

  bool get isOpen;

  /// Decoded text messages from the device, one per frame.
  Stream<String> get messages;

  /// Connection lifecycle; emits `closed` exactly once per connect, with the reason when known.
  Stream<TransportEvent> get events;

  Future<void> connect();

  /// Returns false when the transport is not open.
  bool send(String text);

  bool sendBinary(Uint8List data);

  Future<void> close();
}

class TransportEvent {
  const TransportEvent(this.state, [this.error]);
  final TransportState state;
  final Object? error;
  @override
  String toString() => 'TransportEvent($state${error != null ? ', $error' : ''})';
}

/// Creates a fresh [Transport] per connection attempt so the session can reconnect.
typedef TransportFactory = Transport Function();

/// A transport that delivers messages in chunks (BLE): true while a message is being reassembled,
/// so the renderer can show progress for the multi-KB `ui`.
abstract class ChunkedTransport {
  ValueListenable<bool> get receiving;
}

/// Thrown by connect() when the OS refused a permission the medium needs; the UI shows settings help.
class PermissionDenied implements Exception {
  const PermissionDenied(this.what);
  final String what;
  @override
  String toString() => 'permission denied: $what';
}
