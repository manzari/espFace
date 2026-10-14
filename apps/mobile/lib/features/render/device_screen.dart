import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/platform/app_settings.dart';
import '../../core/session/session.dart';
import '../../core/transport/transport.dart';
import '../../core/transport/transport_chooser.dart';
import '../devices/devices_repository.dart';
import 'common.dart';
import 'icons.dart';
import 'layout.dart';
import 'overlays.dart';

/// The device UI: pages as bottom nav (narrow) or tabs (wide), toasts, device dialogs, PIN pairing.
class DeviceScreen extends ConsumerStatefulWidget {
  const DeviceScreen({super.key, required this.deviceKey});
  final String deviceKey;
  @override
  ConsumerState<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends ConsumerState<DeviceScreen> {
  Session? _session;
  bool _pinShown = false;

  void _onSession() {
    final s = _session;
    if (s == null || !mounted) return;
    if ((s.state == ConnState.pin || s.state == ConnState.locked) && !_pinShown) {
      _pinShown = true;
      final name = s.store.device?.name ?? 'Device';
      showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => PinDialog(session: s, deviceName: name)).then((cancelled) {
        _pinShown = false;
        if (cancelled == false && mounted) {
          s.stop();
          context.go('/');
        }
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dev = ref.watch(devicesProvider.select((l) => l.where((d) => d.key == widget.deviceKey).firstOrNull));
    if (dev == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Unknown device')));
    final bundle = ref.watch(sessionProvider(widget.deviceKey));
    if (_session != bundle.session) {
      _session?.removeListener(_onSession);
      _session = bundle.session..addListener(_onSession);
      WidgetsBinding.instance.addPostFrameCallback((_) => _onSession());
    }
    final wide = ref.watch(themeProvider.select((s) => s.wide));
    final store = bundle.store;
    final session = bundle.session;
    return RenderScope(
      store: store,
      actions: session,
      child: DialogHost(
        child: StoreListener(
          keyName: 'layout',
          builder: (c) => StoreListener(
            keyName: 'page',
            builder: (c) => StoreListener(
              keyName: 'device',
              builder: (c) {
                final pages = store.pages();
                final current = pages.where((p) => p.id == store.page).firstOrNull ?? pages.firstOrNull;
                final wideScreen = MediaQuery.sizeOf(c).width >= 700;
                final tabs = pages.length > 1;
                final name = store.device?.name ?? dev.name;
                return Scaffold(
                  appBar: AppBar(
                    leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
                    title: Row(children: [
                      _ConnDot(state: session.state),
                      const SizedBox(width: 8),
                      Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
                      TransportChip(chooser: bundle.chooser),
                      const SizedBox(width: 8),
                      if (store.device?.proj != null) Text(store.device!.proj!, style: Theme.of(c).textTheme.labelMedium?.copyWith(color: Theme.of(c).colorScheme.onSurfaceVariant)),
                    ]),
                    actions: [IconButton(icon: const Icon(Icons.settings), tooltip: 'System and settings', onPressed: () => context.go('/d/${Uri.encodeComponent(widget.deviceKey)}/system'))],
                    bottom: tabs && wideScreen
                        ? PreferredSize(
                            preferredSize: const Size.fromHeight(48),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(children: [
                                  for (final p in pages)
                                    TextButton.icon(
                                      style: TextButton.styleFrom(foregroundColor: p.id == current?.id ? Theme.of(c).colorScheme.primary : Theme.of(c).colorScheme.onSurfaceVariant),
                                      onPressed: () => session.page(p.id),
                                      icon: Icon(iconFor(p.icon, Icons.tab), size: 18),
                                      label: Text(p.lbl),
                                    ),
                                ]),
                              ),
                            ),
                          )
                        : null,
                  ),
                  body: Stack(children: [
                    Column(children: [
                      _Banner(session: session),
                      Expanded(
                        child: current == null
                            ? ValueListenableBuilder<bool>(
                                valueListenable: bundle.chooser.receiving,
                                builder: (c, receiving, _) => Center(
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    if (receiving) const Padding(padding: EdgeInsets.only(bottom: 12), child: CircularProgressIndicator()),
                                    Text(
                                      receiving
                                          ? 'Receiving the UI over ${bundle.chooser.active.value?.label ?? 'BLE'}'
                                          : session.state == ConnState.ready
                                              ? 'This device has no widgets.'
                                              : 'Waiting for the device',
                                      style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant),
                                    ),
                                  ]),
                                ),
                              )
                            : PageBody(key: ValueKey('page:${current.id}'), page: current, wide: wide),
                      ),
                    ]),
                    Positioned(left: 12, right: 12, bottom: 12, child: const ToastOverlay()),
                  ]),
                  bottomNavigationBar: tabs && !wideScreen
                      ? NavigationBar(
                          selectedIndex: pages.indexWhere((p) => p.id == current?.id).clamp(0, pages.length - 1),
                          onDestinationSelected: (i) => session.page(pages[i].id),
                          destinations: [for (final p in pages) NavigationDestination(icon: Icon(iconFor(p.icon, Icons.tab)), label: p.lbl)],
                        )
                      : null,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Which medium the session is on (WiFi/BLE/USB/Bluetooth) plus a spinner while a chunked message arrives.
class TransportChip extends StatelessWidget {
  const TransportChip({super.key, required this.chooser});
  final TransportChooser chooser;

  static IconData iconFor(TransportKind k) => switch (k) {
        TransportKind.wifi => Icons.wifi,
        TransportKind.ble => Icons.bluetooth_searching,
        TransportKind.usb => Icons.usb,
        TransportKind.bt => Icons.bluetooth,
      };

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TransportKind?>(
        valueListenable: chooser.active,
        builder: (c, kind, _) {
          if (kind == null) return const SizedBox.shrink();
          final cs = Theme.of(c).colorScheme;
          return ValueListenableBuilder<bool>(
            valueListenable: chooser.receiving,
            builder: (c, receiving, _) => Tooltip(
              message: receiving ? 'receiving over ${kind.label}' : 'connected over ${kind.label}',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  receiving ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(iconFor(kind), size: 14, color: cs.onSecondaryContainer),
                  const SizedBox(width: 4),
                  Text(kind.label, style: Theme.of(c).textTheme.labelSmall?.copyWith(color: cs.onSecondaryContainer)),
                ]),
              ),
            ),
          );
        },
      );
}

class _ConnDot extends StatelessWidget {
  const _ConnDot({required this.state});
  final ConnState state;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (state) {
      ConnState.ready => Colors.green,
      ConnState.connecting => Colors.orange,
      ConnState.pin || ConnState.locked => cs.primary,
      _ => cs.error,
    };
    return Tooltip(message: state.name, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)));
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.session});
  final Session session;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: session,
        builder: (c, _) => Ticker(builder: (c) {
          final cs = Theme.of(c).colorScheme;
          final denied = session.lastError is PermissionDenied;
          final left = session.retryAt?.difference(DateTime.now()).inSeconds ?? 0;
          final when = session.inBackground ? ' when the app returns' : left > 0 ? ' in $left s' : '';
          final (text, bg) = switch (session.state) {
            ConnState.offline when denied => ('${(session.lastError as PermissionDenied).what} permission denied. Allow it in the app settings to connect.', cs.errorContainer),
            ConnState.offline when session.busy => ('Device is full (too many clients), retrying$when', cs.errorContainer),
            ConnState.offline => ('Connection lost, reconnecting$when', cs.errorContainer),
            ConnState.connecting => ('Connecting to ${session.label}', cs.surfaceContainerHighest),
            ConnState.stopped => ('Disconnected', cs.surfaceContainerHighest),
            _ => (null, null),
          };
          if (text == null) return const SizedBox.shrink();
          return Material(
            color: bg,
            child: InkWell(
              onTap: session.state == ConnState.stopped ? session.start : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  Expanded(child: Text(text, style: Theme.of(c).textTheme.bodySmall)),
                  if (denied && session.state == ConnState.offline) TextButton(onPressed: openAppSettings, child: const Text('Settings')),
                  if (!denied && session.state == ConnState.offline) TextButton(onPressed: session.reconnect, child: const Text('Retry now')),
                ]),
              ),
            ),
          );
        }),
      );
}
