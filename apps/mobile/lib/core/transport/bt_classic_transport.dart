import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_classic/flutter_blue_classic.dart';

import 'stream_transport.dart';
import 'transport.dart';

/// Bluetooth Classic SPP (Android only, `flutter_blue_classic`): the device must be paired in system settings first.
class BtClassicTransport extends StreamTransport {
  BtClassicTransport(this.address, {Duration connectTimeout = const Duration(seconds: 20)})
      : super(label: 'bt://$address', opener: () => _openSocket(address, connectTimeout));

  final String address;

  static Future<List<BluetoothDevice>> pairedDevices() async => await FlutterBlueClassic().bondedDevices ?? const [];

  static Future<ByteLink> _openSocket(String address, Duration timeout) async {
    final bt = FlutterBlueClassic();
    final state = await bt.adapterStateNow;
    if (state == BluetoothAdapterState.off || state == BluetoothAdapterState.turningOff) throw StateError('Bluetooth is off');
    final BluetoothConnection? c;
    try {
      c = await bt.connect(address).timeout(timeout);
    } catch (e) {
      if (e.toString().toLowerCase().contains('permission')) throw PermissionDenied('Bluetooth');
      rethrow;
    }
    if (c == null) throw StateError('could not open SPP socket to $address');
    return _SppLink(c);
  }
}

class _SppLink implements ByteLink {
  _SppLink(this.conn);
  final BluetoothConnection conn;
  @override
  Stream<Uint8List> get input => conn.input ?? const Stream.empty();
  @override
  Future<void> write(Uint8List data) async => conn.output.add(data);
  @override
  Future<void> close() async {
    try {
      await conn.close();
    } catch (_) {}
  }
}
