import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/render/widgets/inputs.dart';
import 'providers.dart';
import 'theme.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(themeProvider);
    final n = ref.read(themeProvider.notifier);
    final flavor = ref.watch(flavorProvider);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        const _Head('Appearance'),
        ListTile(
          title: const Text('Theme'),
          trailing: SegmentedButton<ThemeMode>(
            segments: const [ButtonSegment(value: ThemeMode.system, label: Text('auto')), ButtonSegment(value: ThemeMode.light, label: Text('light')), ButtonSegment(value: ThemeMode.dark, label: Text('dark'))],
            selected: {s.mode},
            showSelectedIcon: false,
            onSelectionChanged: (v) => n.update(s.copyWith(mode: v.first)),
          ),
        ),
        ListTile(
          title: const Text('Accent'),
          subtitle: Text(flavor.accent != null ? 'fixed by this build' : (s.accent == null ? 'dynamic (system)' : '#${s.accent!.toARGB32().toRadixString(16).substring(2)}')),
          trailing: Container(width: 28, height: 28, decoration: BoxDecoration(color: flavor.accent ?? s.accent ?? cs.primary, shape: BoxShape.circle, border: Border.all(color: cs.outline))),
          enabled: flavor.accent == null,
          onTap: flavor.accent != null
              ? null
              : () async {
                  final v = await showDialog<int>(context: context, builder: (_) => ColorPickerDialog(initial: (s.accent ?? cs.primary).toARGB32() & 0xffffff));
                  if (v != null) n.update(s.copyWith(accent: Color(0xff000000 | v)));
                },
          onLongPress: () => n.update(s.copyWith(clearAccent: true)),
        ),
        ListTile(
          title: const Text('Font size'),
          subtitle: Slider(value: s.scale, min: 0.8, max: 1.4, divisions: 12, label: '${(s.scale * 100).round()}%', onChanged: (v) => n.update(s.copyWith(scale: v))),
        ),
        SwitchListTile(title: const Text('Wide layout'), subtitle: const Text('Centers the device UI on large screens'), value: s.wide, onChanged: (v) => n.update(s.copyWith(wide: v))),
        const _Head('Network'),
        SwitchListTile(
          title: const Text('GitHub release check'),
          subtitle: const Text('Lets the system page query github.com for newer firmware when you tap "Check". Off keeps the app fully offline.'),
          value: s.releaseCheck,
          onChanged: (v) => n.update(s.copyWith(releaseCheck: v)),
        ),
        const _Head('About'),
        ListTile(title: Text(flavor.appName), subtitle: const Text('espFace protocol v1 client. MIT licensed. Nothing leaves the local network except the release check and map tiles.')),
      ]),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
