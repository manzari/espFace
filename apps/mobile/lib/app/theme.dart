import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'flavor.dart';
import 'providers.dart';

/// User appearance settings plus the opt-in release check (offline by default).
class ThemeSettings {
  const ThemeSettings({this.mode = ThemeMode.system, this.accent, this.scale = 1.0, this.wide = false, this.releaseCheck = false});
  final ThemeMode mode;
  final Color? accent;
  final double scale;
  final bool wide;
  final bool releaseCheck;

  ThemeSettings copyWith({ThemeMode? mode, Color? accent, bool clearAccent = false, double? scale, bool? wide, bool? releaseCheck}) => ThemeSettings(
        mode: mode ?? this.mode,
        accent: clearAccent ? null : (accent ?? this.accent),
        scale: scale ?? this.scale,
        wide: wide ?? this.wide,
        releaseCheck: releaseCheck ?? this.releaseCheck,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'accent': ?accent?.toARGB32(),
        'scale': scale,
        'wide': wide,
        'releaseCheck': releaseCheck,
      };

  static ThemeSettings fromJson(Map<String, dynamic> j, {bool releaseDefault = false}) => ThemeSettings(
        mode: ThemeMode.values.firstWhere((m) => m.name == j['mode'], orElse: () => ThemeMode.system),
        accent: j['accent'] is int ? Color(j['accent'] as int) : null,
        scale: (j['scale'] is num ? (j['scale'] as num).toDouble() : 1.0).clamp(0.8, 1.4),
        wide: j['wide'] == true,
        releaseCheck: j['releaseCheck'] is bool ? j['releaseCheck'] as bool : releaseDefault,
      );
}

const _key = 'espface.theme';

class ThemeNotifier extends Notifier<ThemeSettings> {
  @override
  ThemeSettings build() {
    final prefs = ref.watch(prefsProvider);
    final flavor = ref.watch(flavorProvider);
    final raw = prefs.getString(_key);
    if (raw == null) return ThemeSettings(releaseCheck: flavor.releaseCheckDefault);
    try {
      return ThemeSettings.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map), releaseDefault: flavor.releaseCheckDefault);
    } catch (_) {
      return ThemeSettings(releaseCheck: flavor.releaseCheckDefault);
    }
  }

  void update(ThemeSettings s) {
    state = s;
    ref.read(prefsProvider).setString(_key, jsonEncode(s.toJson()));
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeSettings>(ThemeNotifier.new);

ThemeData buildTheme({required Brightness brightness, required ThemeSettings s, required Flavor flavor, ColorScheme? dynamic}) {
  final seed = flavor.accent ?? s.accent;
  final scheme = seed != null
      ? ColorScheme.fromSeed(seedColor: seed, brightness: brightness)
      : (dynamic ?? ColorScheme.fromSeed(seedColor: const Color(0xff2f7df6), brightness: brightness));
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    brightness: brightness,
    cardTheme: const CardThemeData(margin: EdgeInsets.zero),
    inputDecorationTheme: const InputDecorationTheme(isDense: true),
  );
}
