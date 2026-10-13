import 'dart:typed_data';

enum TransportState { connecting, open, closed }

/// One connection to a device: text messages in both directions, binary frames for OTA.
/// WsTransport is the only implementation in phase 3; BLE and stream transports (phase 5)
/// implement the same contract so the session never knows the medium.
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
