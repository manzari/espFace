import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'transport.dart';

/// espFace GATT service (PROTOCOL.md 2): RX write, TX notify, INFO read (`name\0id`).
const bleServiceUuid = '0000ea00-0000-1000-8000-00805f9b34fb';
const bleRxUuid = '0000ea01-0000-1000-8000-00805f9b34fb';
const bleTxUuid = '0000ea02-0000-1000-8000-00805f9b34fb';
const bleInfoUuid = '0000ea03-0000-1000-8000-00805f9b34fb';

/// An open GATT connection to an espFace peripheral, TX already subscribed. [BleTransport] only talks to this
/// interface so the framing logic is testable without a radio.
abstract class BleChannel {
  int get mtu;
  Stream<int> get mtuChanges;
  Stream<List<int>> get notifications;

  /// Emits once with the reason when the link drops.
  Stream<Object?> get disconnected;
  bool get writeWithoutResponse;
  Future<void> write(List<int> packet, {required bool withoutResponse});
  Future<List<int>> readInfo();
  Future<void> close();
}

abstract class BleGatt {
  Future<BleChannel> open(String id, {Duration timeout, int mtu});
}

/// Parses the INFO characteristic: UTF-8 name, one NUL byte, six-hex-digit id.
(String name, String id)? parseBleInfo(List<int> bytes) {
  final nul = bytes.indexOf(0);
  if (nul < 0) return null;
  final name = utf8.decode(bytes.sublist(0, nul), allowMalformed: true);
  final id = utf8.decode(bytes.sublist(nul + 1), allowMalformed: true).trim();
  if (id.isEmpty) return null;
  return (name, id);
}

/// `flutter_blue_plus` implementation. Android runtime permissions (BLUETOOTH_SCAN/CONNECT on 12+, fine location
/// before) are requested by the plugin itself; a refusal surfaces as [PermissionDenied].
class FbpGatt implements BleGatt {
  const FbpGatt();

  static Future<void> ensureAdapter() async {
    if (!await FlutterBluePlus.isSupported) throw StateError('this phone has no Bluetooth LE');
    final st = await FlutterBluePlus.adapterState.first;
    if (st == BluetoothAdapterState.unauthorized) throw const PermissionDenied('Bluetooth');
    if (st == BluetoothAdapterState.off || st == BluetoothAdapterState.turningOff) throw StateError('Bluetooth is off');
  }

  static Object mapError(Object e) {
    if (e is FlutterBluePlusException && (e.description ?? '').toLowerCase().contains('permission')) return PermissionDenied(e.description ?? 'Bluetooth');
    return e;
  }

  @override
  Future<BleChannel> open(String id, {Duration timeout = const Duration(seconds: 20), int mtu = 512}) async {
    await ensureAdapter();
    final dev = BluetoothDevice.fromId(id);
    try {
      await dev.connect(timeout: timeout, mtu: mtu);
      final services = await dev.discoverServices();
      final svc = services.where((s) => s.uuid == Guid(bleServiceUuid)).firstOrNull;
      if (svc == null) throw StateError('no espFace service on $id');
      BluetoothCharacteristic chr(String uuid) {
        final c = svc.characteristics.where((c) => c.uuid == Guid(uuid)).firstOrNull;
        if (c == null) throw StateError('characteristic $uuid missing');
        return c;
      }

      final rx = chr(bleRxUuid), tx = chr(bleTxUuid);
      final info = svc.characteristics.where((c) => c.uuid == Guid(bleInfoUuid)).firstOrNull;
      await tx.setNotifyValue(true);
      return _FbpChannel(dev, rx, tx, info);
    } catch (e) {
      try {
        await dev.disconnect();
      } catch (_) {}
      throw mapError(e);
    }
  }
}

class _FbpChannel implements BleChannel {
  _FbpChannel(this.dev, this.rx, this.tx, this.info);
  final BluetoothDevice dev;
  final BluetoothCharacteristic rx, tx;
  final BluetoothCharacteristic? info;

  @override
  int get mtu => dev.mtuNow;
  @override
  Stream<int> get mtuChanges => dev.mtu;
  @override
  Stream<List<int>> get notifications => tx.onValueReceived;
  @override
  Stream<Object?> get disconnected => dev.connectionState.where((s) => s == BluetoothConnectionState.disconnected).map((_) => dev.disconnectReason?.description ?? 'disconnected').take(1);
  @override
  bool get writeWithoutResponse => rx.properties.writeWithoutResponse;
  @override
  Future<void> write(List<int> packet, {required bool withoutResponse}) => rx.write(packet, withoutResponse: withoutResponse);
  @override
  Future<List<int>> readInfo() async => info == null ? const [] : await info!.read();
  @override
  Future<void> close() => dev.disconnect();
}

/// Connects, reads INFO and disconnects: used by the add sheet to learn name/id before saving.
Future<(String name, String id)?> readBleInfo(String id, {BleGatt gatt = const FbpGatt(), Duration timeout = const Duration(seconds: 15)}) async {
  final ch = await gatt.open(id, timeout: timeout, mtu: 128);
  try {
    return parseBleInfo(await ch.readInfo().timeout(timeout));
  } finally {
    await ch.close();
  }
}
