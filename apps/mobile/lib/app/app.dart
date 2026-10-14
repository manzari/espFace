import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'router.dart';
import 'theme.dart';

class EspFaceApp extends ConsumerWidget {
  const EspFaceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeProvider);
    final flavor = ref.watch(flavorProvider);
    final router = ref.watch(routerProvider);
    return DynamicColorBuilder(
      builder: (light, dark) => MaterialApp.router(
        title: flavor.appName,
        debugShowCheckedModeBanner: false,
        themeMode: settings.mode,
        theme: buildTheme(brightness: Brightness.light, s: settings, flavor: flavor, dynamic: light),
        darkTheme: buildTheme(brightness: Brightness.dark, s: settings, flavor: flavor, dynamic: dark),
        routerConfig: router,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(settings.scale)),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
