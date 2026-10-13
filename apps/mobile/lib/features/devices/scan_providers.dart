import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/transport/ble_gatt.dart';
import '../../core/transport/bt_classic_transport.dart';
import '../../core/transport/usb_serial_transport.dart';
import 'device.dart';

/// BLE scan filtered on the espFace service UUID while the BLE section of the add sheet is shown.
/// The plugin asks for the Bluetooth permissions itself; a refusal lands in [error] as a PermissionDenied.
class BleScanNotifier extends Notifier<List<BleFound>> {
  StreamSubscription? _sub;
  bool _disposed = false;
  Object? error;

  @override
  List<BleFound> build() {
    ref.onDispose(_stop);
    _start();
    return const [];
  }

  Future<void> _start() async {
    try {
      await FbpGatt.ensureAdapter();
      _sub = FlutterBluePlus.onScanResults.listen((rs) {
        if (_disposed) return;
        state = [for (final r in rs) fromScan(r.device.remoteId.str, r.advertisementData.advName, r.device.platformName, r.rssi)];
      }, onError: (Object e) => _fail(e));
      await FlutterBluePlus.startScan(withServices: [Guid(bleServiceUuid)], continuousUpdates: true, removeIfGone: const Duration(seconds: 15));
    } catch (e) {
      _fail(e);
    }
  }

  void _fail(Object e) {
    error = FbpGatt.mapError(e);
    if (!_disposed) state = const [];
  }

  static BleFound fromScan(String id, String advName, String platformName, int rssi) => BleFound(bleId: id, name: advName.isNotEmpty ? advName : (platformName.isNotEmpty ? platformName : id), rssi: rssi);

  Future<void> _stop() async {
    _disposed = true;
    await _sub?.cancel();
    _sub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }
}

final bleScanProvider = NotifierProvider.autoDispose<BleScanNotifier, List<BleFound>>(BleScanNotifier.new);

/// Attached USB serial adapters (Android), refreshed each time the USB section opens.
final usbPortsProvider = FutureProvider.autoDispose<List<UsbPortInfo>>((ref) async {
  final ports = await UsbSerialTransport.listPorts();
  return [for (final p in ports) UsbPortInfo(port: UsbSerialTransport.portId(p), name: UsbSerialTransport.portName(p))];
});

/// Paired Bluetooth Classic devices (Android); pairing itself happens in the system settings.
final btPairedProvider = FutureProvider.autoDispose<List<BtPairedInfo>>((ref) async {
  final devs = await BtClassicTransport.pairedDevices();
  return [for (final d in devs) BtPairedInfo(address: d.address, name: d.name ?? d.alias ?? '')];
});
