import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/proto/values.dart';
import '../../core/session/session.dart';
import '../../core/transport/transport.dart';
import '../../core/transport/usb_serial_transport.dart';
import '../devices/devices_repository.dart';
import '../render/common.dart';
import '../render/widgets/log_table.dart';
import 'ota.dart';
import 'release_check.dart';

/// Device system pages: info, WiFi, security, reboot, OTA, release check, console, connection. All gated by `caps`.
class SystemPage extends ConsumerWidget {
  const SystemPage({super.key, required this.deviceKey});
  final String deviceKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundle = ref.watch(sessionProvider(deviceKey));
    return RenderScope(
      store: bundle.store,
      actions: bundle.session,
      child: Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/d/${Uri.encodeComponent(deviceKey)}')), title: const Text('System')),
        body: StoreListener(
          keyName: 'device',
          builder: (c) => ListView(
            padding: const EdgeInsets.all(12),
            children: [
              InfoSection(session: bundle.session),
              WifiSection(session: bundle.session),
              SecuritySection(session: bundle.session),
              RebootSection(session: bundle.session),
              OtaSection(session: bundle.session),
              const ReleaseSection(),
              const ConsoleSection(),
              ConnectionSection(deviceKey: deviceKey, bundle: bundle),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card with a title; greyed out with a note when the device lacks the capability.
class Section extends StatelessWidget {
  const Section({super.key, required this.title, required this.icon, this.enabled = true, this.disabledNote, required this.child});
  final String title;
  final IconData icon;
  final bool enabled;
  final String? disabledNote;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [Icon(icon, size: 18, color: theme.colorScheme.primary), const SizedBox(width: 6), Text(title, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary))]),
            const SizedBox(height: 8),
            if (enabled) child else Opacity(opacity: 0.5, child: IgnorePointer(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text(disabledNote ?? '$title not available on this device.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)), child]))),
          ]),
        ),
      ),
    );
  }
}

class KV extends StatelessWidget {
  const KV(this.rows, {super.key});
  final List<(String, String)> rows;
  @override
  Widget build(BuildContext context) => Table(
        columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
        children: [
          for (final (k, v) in rows)
            TableRow(children: [
              Padding(padding: const EdgeInsets.fromLTRB(0, 3, 12, 3), child: Text(k, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
              Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: SelectableText(v)),
            ]),
        ],
      );
}

Future<bool> confirm(BuildContext context, String title, String msg) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('OK'))],
      ),
    ) ==
    true;

class InfoSection extends StatefulWidget {
  const InfoSection({super.key, required this.session});
  final Session session;
  @override
  State<InfoSection> createState() => _InfoSectionState();
}

class _InfoSectionState extends State<InfoSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.store.hasCap('info')) widget.session.sys('info');
    });
  }

  @override
  Widget build(BuildContext context) => StoreListener(
        keyName: 'sys:info',
        builder: (c) {
          final store = c.store;
          final d = store.device, i = store.sysInfo;
          return Section(
            title: 'Device',
            icon: Icons.info,
            enabled: store.hasCap('info'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              KV([
                ('Name', '${d?.name ?? '-'}  ${d?.id ?? ''}'),
                if (d?.proj != null) ('Project', d!.proj!),
                ('Firmware', i?.fw ?? d?.fw ?? '-'),
                if (i?.repo != null) ('Repository', 'github.com/${i!.repo}'),
                if (i?.about != null) ('About', i!.about!),
                ('Chip', i?.chip ?? '-'),
                ('Reboot reason', i?.rr ?? '-'),
                ('Heap', '${fmtKb(i?.heap)} free, min ${fmtKb(i?.heapmin)}'),
                ('Uptime', fmtUptime(i?.up)),
                ('IP', i?.ip ?? '-'),
                ('RSSI', i?.rssi != null ? '${i!.rssi} dBm' : '-'),
                ('Time', (i?.time ?? 0) > 0 ? DateTime.fromMillisecondsSinceEpoch(i!.time! * 1000).toLocal().toString().split('.').first : 'not set'),
                ('Clients', '${i?.clients ?? '-'}'),
                ('Protocol', 'v${d?.v ?? '-'} · caps ${d?.caps.isNotEmpty == true ? d!.caps.join(', ') : 'none'}'),
              ]),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: () => widget.session.sys('info'), icon: const Icon(Icons.refresh), label: const Text('Refresh'))),
            ]),
          );
        },
      );
}

class WifiSection extends StatefulWidget {
  const WifiSection({super.key, required this.session});
  final Session session;
  @override
  State<WifiSection> createState() => _WifiSectionState();
}

class _WifiSectionState extends State<WifiSection> {
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.store.hasCap('wifi')) widget.session.sys('wifi.status');
    });
  }

  Future<void> _join(BuildContext context, String ssid, bool enc) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Join $ssid'),
        content: enc ? TextField(controller: ctl, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()), onSubmitted: (_) => Navigator.pop(c, true)) : const Text('Open network'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Connect'))],
      ),
    );
    if (ok == true) widget.session.sys('wifi.set', {'ssid': ssid, 'pass': ctl.text});
  }

  Future<void> _joinOther(BuildContext context) async {
    final ssid = TextEditingController(), pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Other network'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: ssid, autofocus: true, decoration: const InputDecoration(labelText: 'SSID', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Connect'))],
      ),
    );
    if (ok == true && ssid.text.isNotEmpty) widget.session.sys('wifi.set', {'ssid': ssid.text, 'pass': pass.text});
  }

  @override
  Widget build(BuildContext context) => StoreListener(
        keyName: 'sys',
        builder: (c) {
          final store = c.store;
          final w = store.wifi, i = store.sysInfo, scan = store.wifiScan;
          if (scan != null && _scanning) _scanning = false;
          return Section(
            title: 'WiFi',
            icon: Icons.wifi,
            enabled: store.hasCap('wifi'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              KV([
                ('State', w?.st ?? '-'),
                ('SSID', w?.ssid ?? i?.ssid ?? '-'),
                ('IP', w?.ip ?? i?.ip ?? '-'),
                ('RSSI', '${w?.rssi ?? i?.rssi ?? '-'} dBm'),
                ('MAC', i?.mac ?? '-'),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                OutlinedButton.icon(
                  onPressed: _scanning
                      ? null
                      : () {
                          setState(() => _scanning = true);
                          widget.session.sys('wifi.scan');
                        },
                  icon: _scanning ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.radar),
                  label: const Text('Scan'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(onPressed: () => _joinOther(c), icon: const Icon(Icons.edit), label: const Text('Other network')),
              ]),
              if (scan != null)
                for (final ap in scan)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(ap.rssi > -60 ? Icons.network_wifi : ap.rssi > -75 ? Icons.network_wifi_3_bar : Icons.network_wifi_1_bar),
                    title: Text(ap.ssid),
                    subtitle: Text('${ap.rssi} dBm'),
                    trailing: ap.enc ? const Icon(Icons.lock, size: 16) : null,
                    onTap: () => _join(c, ap.ssid, ap.enc),
                  ),
            ]),
          );
        },
      );
}

class SecuritySection extends StatefulWidget {
  const SecuritySection({super.key, required this.session});
  final Session session;
  @override
  State<SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<SecuritySection> {
  final _pin = TextEditingController();
  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final valid = _pin.text.isEmpty || (_pin.text.length >= 4 && _pin.text.length <= 32);
    return Section(
      title: 'Security',
      icon: Icons.lock,
      enabled: store.hasCap('pin'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Current auth: ${store.device?.auth == 'pin' ? 'PIN required' : 'open'}. Changing the PIN or revoking drops every paired client, including this one.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _pin,
              obscureText: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'New PIN (empty disables)', border: const OutlineInputBorder(), errorText: valid ? null : '4 to 32 characters'),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: valid
                ? () async {
                    if (!await confirm(context, 'Change PIN', _pin.text.isEmpty ? 'Disable the PIN on the device?' : 'Set the new PIN? All pairings are deleted.')) return;
                    await widget.session.forget();
                    widget.session.sys('pin.set', {'pin': _pin.text});
                    _pin.clear();
                  }
                : null,
            child: const Text('Set'),
          ),
        ]),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              if (!await confirm(context, 'Revoke', 'Delete all session tokens on the device?')) return;
              await widget.session.forget();
              widget.session.sys('revoke');
            },
            icon: const Icon(Icons.key_off),
            label: const Text('Revoke all pairings'),
          ),
        ),
      ]),
    );
  }
}

class RebootSection extends StatelessWidget {
  const RebootSection({super.key, required this.session});
  final Session session;
  @override
  Widget build(BuildContext context) => Section(
        title: 'Reboot',
        icon: Icons.power_settings_new,
        enabled: context.store.hasCap('reboot'),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: () async {
              if (await confirm(context, 'Reboot', 'Reboot the device now?')) session.sys('reboot');
            },
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reboot device'),
          ),
        ),
      );
}

class OtaSection extends StatefulWidget {
  const OtaSection({super.key, required this.session});
  final Session session;
  @override
  State<OtaSection> createState() => _OtaSectionState();
}

class _OtaSectionState extends State<OtaSection> {
  OtaPush? _push;
  final _url = TextEditingController();
  String? _file;

  @override
  void dispose() {
    _push?.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _pickAndPush() async {
    final files = await FilePicker.pickFiles(type: FileType.any, dialogTitle: 'Firmware .bin');
    if (files.isEmpty || !mounted) return;
    final f = files.first;
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    final store = context.store;
    if (!await confirm(context, 'Flash firmware', 'Upload ${f.name} (${fmtKb(bytes.length)}) to the device?')) return;
    if (!mounted) return;
    setState(() => _file = f.name);
    final p = _push ??= OtaPush(session: widget.session, store: store)..addListener(() => mounted ? setState(() {}) : null);
    await p.run(bytes);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) => StoreListener(
          keyName: 'sys',
          builder: (c) {
            final store = c.store;
            final binary = widget.session.supportsBinary;
            final push = store.hasCap('ota') && binary;
            final byUrl = store.hasCap('otaurl');
            final ota = store.ota;
            final p = _push;
            final cs = Theme.of(c).colorScheme;
            return Section(
              title: 'Firmware update',
              icon: Icons.upload,
              enabled: push || byUrl,
              disabledNote: 'OTA not available on this device or transport.',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // The push half only exists on a transport with binary frames (WiFi); BLE and serial keep ota.url.
                if (!binary)
                  Text('OTA push needs WiFi.', style: TextStyle(color: cs.onSurfaceVariant))
                else ...[
                  Row(children: [
                    FilledButton.tonalIcon(onPressed: push && !(p?.running ?? false) ? _pickAndPush : null, icon: const Icon(Icons.file_open), label: const Text('Upload .bin')),
                    const SizedBox(width: 8),
                    if (p?.running ?? false) OutlinedButton(onPressed: p!.abort, child: const Text('Abort')),
                    if (_file != null) ...[const SizedBox(width: 8), Expanded(child: Text(_file!, overflow: TextOverflow.ellipsis))],
                  ]),
                  if (p != null && (p.running || ota != null)) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: ota != null ? ota.pct / 100 : p.sentFraction),
                    const SizedBox(height: 4),
                    Text(ota != null ? 'device ${ota.pct}%' : 'sent ${(p.sentFraction * 100).round()}%'),
                  ],
                  if (p?.error != null) Text(p!.error!, style: TextStyle(color: cs.error)),
                  if (ota?.done == true) Text(ota!.ok == true ? 'Update done, device reboots.' : 'Update failed: ${ota.msg ?? 'unknown error'}', style: TextStyle(color: ota.ok == true ? cs.primary : cs.error)),
                ],
                const Divider(height: 24),
              TextField(controller: _url, enabled: byUrl, decoration: const InputDecoration(labelText: 'Update from URL (http/https .bin)', border: OutlineInputBorder()), keyboardType: TextInputType.url),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: byUrl
                      ? () async {
                          final u = _url.text.trim();
                          if (!u.startsWith('http://') && !u.startsWith('https://')) return;
                          if (await confirm(c, 'Update by URL', 'Ask the device to download and flash\n$u?')) widget.session.sys('ota.url', {'url': u});
                        }
                      : null,
                  icon: const Icon(Icons.cloud_download),
                  label: const Text('Update by URL'),
                ),
              ),
            ]),
          );
          },
        ),
      );
}

class ReleaseSection extends ConsumerStatefulWidget {
  const ReleaseSection({super.key});
  @override
  ConsumerState<ReleaseSection> createState() => _ReleaseSectionState();
}

class _ReleaseSectionState extends ConsumerState<ReleaseSection> {
  bool _busy = false;
  ReleaseInfo? _rel;
  String? _err;

  Future<void> _check(String repo) async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final r = await fetchLatestRelease(repo);
      setState(() => _rel = r);
      if (r == null) setState(() => _err = 'No release found');
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = ref.watch(themeProvider.select((s) => s.releaseCheck));
    return StoreListener(
      keyName: 'sys:info',
      builder: (c) {
        final store = c.store;
        final repo = store.sysInfo?.repo;
        final fw = store.sysInfo?.fw ?? store.device?.fw;
        final cs = Theme.of(c).colorScheme;
        final rel = _rel;
        return Section(
          title: 'Release check',
          icon: Icons.new_releases,
          enabled: on && repo != null,
          disabledNote: !on ? 'Off. Enable "GitHub release check" in Settings to query github.com on demand.' : 'The device does not publish a repository.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Repository: ${repo ?? '-'} · installed: ${fw ?? '-'}', style: Theme.of(c).textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(children: [
              OutlinedButton.icon(onPressed: _busy || repo == null ? null : () => _check(repo), icon: const Icon(Icons.search), label: Text(_busy ? 'Checking' : 'Check GitHub')),
              const SizedBox(width: 8),
              if (rel != null && rel.binUrl != null && store.hasCap('otaurl'))
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final actions = c.actions;
                    if (await confirm(c, 'Install ${rel.tag}', 'Ask the device to download\n${rel.binUrl}?')) actions.sys('ota.url', {'url': rel.binUrl!});
                  },
                  icon: const Icon(Icons.system_update),
                  label: const Text('Install'),
                ),
            ]),
            if (rel != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Latest: ${rel.tag}${rel.name != null ? ' (${rel.name})' : ''} · ${rel.isNewerThan(fw) ? 'newer than installed' : 'already installed'}${rel.binUrl == null ? ' · no .bin asset' : ''}')),
            if (_err != null) Text(_err!, style: TextStyle(color: cs.error)),
          ]),
        );
      },
    );
  }
}

class ConsoleSection extends StatelessWidget {
  const ConsoleSection({super.key});
  @override
  Widget build(BuildContext context) => StoreListener(
        keyName: 'console',
        builder: (c) => Section(
          title: 'Console',
          icon: Icons.terminal,
          child: c.store.console.isEmpty ? Text('No device log lines yet.', style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant)) : LogLines(lines: c.store.console, height: 220),
        ),
      );
}

/// Active transport and state, the per-device transport pin (auto = WiFi -> BLE -> serial), USB baud, forget pairing.
class ConnectionSection extends ConsumerWidget {
  const ConnectionSection({super.key, required this.deviceKey, required this.bundle});
  final String deviceKey;
  final SessionBundle bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = bundle.session;
    final dev = ref.watch(devicesProvider.select((l) => l.where((d) => d.key == deviceKey).firstOrNull));
    final repo = ref.read(devicesProvider.notifier);
    final serial = ref.watch(serialSupportedProvider);
    final kinds = dev?.candidates(serialSupported: serial) ?? const [];
    final configured = dev?.configured.where((k) => serial || (k != TransportKind.usb && k != TransportKind.bt)).toList() ?? const [];
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([session, bundle.chooser.active]),
      builder: (context, _) => Section(
        title: 'Connection',
        icon: Icons.bolt,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KV([
            ('Transport', '${bundle.chooser.active.value?.label ?? '-'} · ${session.label}'),
            ('State', session.state.name),
            ('Binary frames', session.supportsBinary ? 'yes (OTA push)' : 'no (OTA by URL only)'),
            if (dev != null) ('Addresses', dev.addressSummary),
          ]),
          if (configured.length > 1) ...[
            const SizedBox(height: 8),
            Text('Preferred transport', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            SegmentedButton<TransportKind?>(
              segments: [
                const ButtonSegment<TransportKind?>(value: null, label: Text('Auto')),
                for (final k in configured) ButtonSegment<TransportKind?>(value: k, label: Text(k.label)),
              ],
              selected: {dev?.preferred},
              showSelectedIcon: false,
              onSelectionChanged: (s) => repo.setPreferred(deviceKey, s.first),
            ),
            Text(dev?.preferred == null ? 'Auto tries ${kinds.map((k) => k.label).join(', then ')}.' : 'Only ${dev!.preferred!.label} is used.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          ],
          if (dev?.usbPort != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Expanded(child: Text('USB baud rate')),
              DropdownButton<int>(
                value: UsbSerialTransport.bauds.contains(dev!.usbBaud) ? dev.usbBaud : 115200,
                items: [for (final b in UsbSerialTransport.bauds) DropdownMenuItem(value: b, child: Text('$b'))],
                onChanged: (b) => b == null ? null : repo.setBaud(deviceKey, b),
              ),
            ]),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () async {
                await session.forget();
                session.reconnect();
              },
              icon: const Icon(Icons.link_off),
              label: const Text('Forget pairing and reconnect'),
            ),
          ),
        ]),
      ),
    );
  }
}
