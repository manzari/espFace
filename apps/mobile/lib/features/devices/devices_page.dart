import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/platform/app_settings.dart';
import '../../core/transport/ble_gatt.dart';
import '../../core/transport/transport.dart';
import '../../core/transport/usb_serial_transport.dart';
import '../render/icons.dart';
import 'device.dart';
import 'devices_repository.dart';
import 'discovery.dart';
import 'scan_providers.dart';

/// Reads name/id of a BLE peripheral before saving it; tests override this with a canned answer.
final bleInfoReaderProvider = Provider<Future<(String, String)?> Function(String bleId)>((_) => (id) => readBleInfo(id));

/// Saved devices grouped by project, drag-to-reorder inside a group, add via discovery / manual / QR / BLE / serial.
class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(devicesProvider);
    final repo = ref.read(devicesProvider.notifier);
    final flavor = ref.watch(flavorProvider);
    final groups = repo.grouped();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(flavor.appName),
        actions: [IconButton(icon: const Icon(Icons.settings), tooltip: 'Settings', onPressed: () => context.go('/settings'))],
      ),
      body: groups.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.devices_other, size: 64, color: cs.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text(flavor.locked ? 'No devices configured in this build.' : 'No devices yet. Tap + to find one on your network, over Bluetooth or USB, enter a host or scan a QR code.', textAlign: TextAlign.center),
                ]),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                for (final (proj, devices) in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(proj.isEmpty ? 'Devices' : proj, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.primary)),
                  ),
                  ReorderableListView(
                    key: ValueKey('group:$proj'),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: !flavor.locked,
                    onReorderItem: (a, b) => repo.reorder(proj, a, b),
                    children: [for (final d in devices) _DeviceTile(key: ValueKey(d.key), device: d, locked: flavor.locked)],
                  ),
                ],
              ],
            ),
      floatingActionButton: flavor.locked ? null : FloatingActionButton(onPressed: () => _showAdd(context), child: const Icon(Icons.add)),
    );
  }

  void _showAdd(BuildContext context) => showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => const AddDeviceSheet());
}

class _DeviceTile extends ConsumerWidget {
  const _DeviceTile({super.key, required this.device, required this.locked});
  final SavedDevice device;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
        leading: CircleAvatar(child: Icon(iconFor(device.icon, Icons.memory))),
        title: Text(device.name),
        subtitle: Text([device.addressSummary, ?device.fw].join(' · ')),
        onTap: () => context.go('/d/${Uri.encodeComponent(device.key)}'),
        trailing: locked
            ? null
            : PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'remove') ref.read(devicesProvider.notifier).remove(device.key);
                  if (v == 'forget') ref.read(tokenStoreProvider).remove(device.id ?? '');
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'forget', child: Text('Forget pairing')),
                  PopupMenuItem(value: 'remove', child: Text('Remove')),
                ],
              ),
      );
}

/// Bottom sheet with one section per medium: WiFi (mDNS, host, QR), BLE scan, USB ports, paired Bluetooth (Android).
class AddDeviceSheet extends ConsumerStatefulWidget {
  const AddDeviceSheet({super.key});
  @override
  ConsumerState<AddDeviceSheet> createState() => _AddDeviceSheetState();
}

class _AddDeviceSheetState extends ConsumerState<AddDeviceSheet> {
  final _host = TextEditingController();
  TransportKind _kind = TransportKind.wifi;
  int _baud = 115200;
  String? _busyBle;

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  void _open(SavedDevice d) {
    Navigator.of(context).pop();
    context.go('/d/${Uri.encodeComponent(d.key)}');
  }

  Future<void> _addBle(BleFound f) async {
    if (_busyBle != null) return;
    setState(() => _busyBle = f.bleId);
    (String, String)? info;
    try {
      info = await ref.read(bleInfoReaderProvider)(f.bleId).timeout(const Duration(seconds: 20));
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busyBle = null);
    _open(ref.read(devicesProvider.notifier).addBle(f.bleId, info?.$1.isNotEmpty == true ? info!.$1 : f.name, protocolId: info?.$2));
  }

  @override
  Widget build(BuildContext context) {
    final serial = ref.watch(serialSupportedProvider);
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Add device', style: tt.titleLarge),
        const SizedBox(height: 12),
        SegmentedButton<TransportKind>(
          segments: [
            const ButtonSegment(value: TransportKind.wifi, label: Text('WiFi'), icon: Icon(Icons.wifi)),
            const ButtonSegment(value: TransportKind.ble, label: Text('BLE'), icon: Icon(Icons.bluetooth_searching)),
            if (serial) const ButtonSegment(value: TransportKind.usb, label: Text('USB'), icon: Icon(Icons.usb)),
            if (serial) const ButtonSegment(value: TransportKind.bt, label: Text('Bluetooth'), icon: Icon(Icons.bluetooth)),
          ],
          selected: {_kind},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _kind = s.first),
        ),
        const SizedBox(height: 12),
        switch (_kind) {
          TransportKind.wifi => _wifi(context),
          TransportKind.ble => _ble(context),
          TransportKind.usb => _usb(context),
          TransportKind.bt => _bt(context),
        },
      ]),
    );
  }

  Widget _wifi(BuildContext context) {
    final found = ref.watch(discoveryProvider);
    final err = ref.read(discoveryProvider.notifier).error;
    final repo = ref.read(devicesProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('On this network', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(width: 8),
        if (err == null) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      if (err != null) Text('Discovery unavailable: $err', style: TextStyle(color: cs.onSurfaceVariant)),
      if (err == null && found.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Searching for _espface._tcp services', style: TextStyle(color: cs.onSurfaceVariant))),
      for (final d in found)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(iconFor(d.icon, Icons.memory)),
          title: Text(d.name),
          subtitle: Text([d.host, ?d.proj].join(' · ')),
          onTap: () => _open(repo.addDiscovered(d)),
        ),
      const Divider(),
      TextField(
        controller: _host,
        decoration: const InputDecoration(labelText: 'Host or IP (optionally :port)', hintText: '192.168.4.1 or boiler.local:8080', border: OutlineInputBorder()),
        keyboardType: TextInputType.url,
        autocorrect: false,
        onSubmitted: (h) => h.trim().isEmpty ? null : _open(repo.addManual(h.trim())),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: FilledButton.icon(onPressed: () => _host.text.trim().isEmpty ? null : _open(repo.addManual(_host.text.trim())), icon: const Icon(Icons.link), label: const Text('Connect'))),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/scan');
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR'),
          ),
        ),
      ]),
    ]);
  }

  Widget _ble(BuildContext context) {
    final found = ref.watch(bleScanProvider);
    final err = ref.read(bleScanProvider.notifier).error;
    final cs = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('Nearby over Bluetooth LE', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(width: 8),
        if (err == null) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      if (err != null) PermissionNote(error: err, what: 'Bluetooth scan'),
      if (err == null && found.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Scanning for the espFace service', style: TextStyle(color: cs.onSurfaceVariant))),
      for (final f in found)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.bluetooth),
          title: Text(f.name),
          subtitle: Text([f.bleId, if (f.rssi != null) '${f.rssi} dBm'].join(' · ')),
          trailing: _busyBle == f.bleId ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
          onTap: () => _addBle(f),
        ),
      Text('OTA push is not available over BLE; the UI loads in chunks.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
    ]);
  }

  Widget _usb(BuildContext context) {
    final ports = ref.watch(usbPortsProvider);
    final cs = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('USB serial adapters', style: Theme.of(context).textTheme.titleSmall)),
        DropdownButton<int>(
          value: _baud,
          items: [for (final b in UsbSerialTransport.bauds) DropdownMenuItem(value: b, child: Text('$b baud'))],
          onChanged: (b) => setState(() => _baud = b ?? _baud),
        ),
        IconButton(icon: const Icon(Icons.refresh), tooltip: 'Rescan', onPressed: () => ref.invalidate(usbPortsProvider)),
      ]),
      switch (ports) {
        AsyncData(:final value) when value.isEmpty => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('No USB serial device attached (needs an OTG cable).', style: TextStyle(color: cs.onSurfaceVariant))),
        AsyncData(:final value) => Column(mainAxisSize: MainAxisSize.min, children: [
            for (final p in value)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.usb),
                title: Text(p.name.isEmpty ? p.port : p.name),
                subtitle: Text(p.port),
                onTap: () => _open(ref.read(devicesProvider.notifier).addUsb(p.port, p.name, baud: _baud)),
              ),
          ]),
        AsyncError(:final error) => Text('USB unavailable: $error', style: TextStyle(color: cs.error)),
        _ => const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator())),
      },
      Text('8N1; Android asks for USB permission on first connect. No OTA push over serial.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
    ]);
  }

  Widget _bt(BuildContext context) {
    final paired = ref.watch(btPairedProvider);
    final cs = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('Paired Bluetooth devices', style: Theme.of(context).textTheme.titleSmall)),
        IconButton(icon: const Icon(Icons.refresh), tooltip: 'Reload', onPressed: () => ref.invalidate(btPairedProvider)),
      ]),
      switch (paired) {
        AsyncData(:final value) when value.isEmpty => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Nothing paired. Pair the device in the Android Bluetooth settings first.', style: TextStyle(color: cs.onSurfaceVariant))),
        AsyncData(:final value) => Column(mainAxisSize: MainAxisSize.min, children: [
            for (final p in value)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bluetooth_connected),
                title: Text(p.name.isEmpty ? p.address : p.name),
                subtitle: Text(p.address),
                onTap: () => _open(ref.read(devicesProvider.notifier).addBt(p.address, p.name)),
              ),
          ]),
        AsyncError(:final error) => PermissionNote(error: error, what: 'Bluetooth'),
        _ => const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator())),
      },
      Text('Bluetooth Classic SPP (ESPFACE_BT_CLASSIC firmware). No OTA push over SPP.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
    ]);
  }
}

/// Explicit permission-denial UX: says what was refused and offers the system settings page.
class PermissionNote extends StatelessWidget {
  const PermissionNote({super.key, required this.error, required this.what});
  final Object error;
  final String what;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (error is! PermissionDenied) return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('$what unavailable: $error', style: TextStyle(color: cs.error)));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(child: Text('$what needs the Bluetooth permission (and Location on Android 11 or older). Allow it in the app settings.', style: TextStyle(color: cs.error))),
        TextButton(onPressed: openAppSettings, child: const Text('Settings')),
      ]),
    );
  }
}
