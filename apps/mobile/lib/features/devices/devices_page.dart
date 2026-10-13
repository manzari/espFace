import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../render/icons.dart';
import 'device.dart';
import 'devices_repository.dart';
import 'discovery.dart';

/// Saved devices grouped by project, drag-to-reorder inside a group, add via discovery / manual / QR.
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
                  Text(flavor.locked ? 'No devices configured in this build.' : 'No devices yet. Tap + to find one on your network, enter a host or scan a QR code.', textAlign: TextAlign.center),
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
        subtitle: Text([device.host, ?device.fw].join(' · ')),
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

class AddDeviceSheet extends ConsumerStatefulWidget {
  const AddDeviceSheet({super.key});
  @override
  ConsumerState<AddDeviceSheet> createState() => _AddDeviceSheetState();
}

class _AddDeviceSheetState extends ConsumerState<AddDeviceSheet> {
  final _host = TextEditingController();

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  void _open(SavedDevice d) {
    Navigator.of(context).pop();
    context.go('/d/${Uri.encodeComponent(d.key)}');
  }

  @override
  Widget build(BuildContext context) {
    final found = ref.watch(discoveryProvider);
    final err = ref.read(discoveryProvider.notifier).error;
    final repo = ref.read(devicesProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Add device', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
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
      ]),
    );
  }
}
