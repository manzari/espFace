import 'package:flutter/material.dart';

/// White-label build configuration from `--dart-define` (see README "White-label builds").
///
/// ESPFACE_APP_NAME   display name (default "espFace")
/// ESPFACE_ACCENT     fixed accent color `#rrggbb` (disables dynamic color and the accent setting)
/// ESPFACE_PROJ       fixed project filter: only devices with this `proj` are listed and discovered
/// ESPFACE_DEVICES    locked device list `Name@host:port,Name2@host2`: no add/remove/reorder
/// ESPFACE_RELEASE_CHECK  "on" to enable the GitHub release check by default (still user-triggered)
class Flavor {
  const Flavor({required this.appName, this.accent, this.proj, this.lockedDevices = const [], this.releaseCheckDefault = false});

  final String appName;
  final Color? accent;
  final String? proj;
  final List<LockedDevice> lockedDevices;
  final bool releaseCheckDefault;

  bool get locked => lockedDevices.isNotEmpty;

  static const _name = String.fromEnvironment('ESPFACE_APP_NAME', defaultValue: 'espFace');
  static const _accent = String.fromEnvironment('ESPFACE_ACCENT');
  static const _proj = String.fromEnvironment('ESPFACE_PROJ');
  static const _devices = String.fromEnvironment('ESPFACE_DEVICES');
  static const _release = String.fromEnvironment('ESPFACE_RELEASE_CHECK');

  static Flavor fromEnvironment() => parse(name: _name, accent: _accent, proj: _proj, devices: _devices, release: _release);

  static Flavor parse({String name = 'espFace', String accent = '', String proj = '', String devices = '', String release = ''}) {
    Color? color;
    if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(accent)) color = Color(0xff000000 | int.parse(accent.substring(1), radix: 16));
    final locked = <LockedDevice>[];
    for (final part in devices.split(',')) {
      final p = part.trim();
      if (p.isEmpty) continue;
      final at = p.indexOf('@');
      locked.add(at < 0 ? LockedDevice(name: p, host: p) : LockedDevice(name: p.substring(0, at).trim(), host: p.substring(at + 1).trim()));
    }
    return Flavor(
      appName: name.isEmpty ? 'espFace' : name,
      accent: color,
      proj: proj.isEmpty ? null : proj,
      lockedDevices: locked,
      releaseCheckDefault: release == 'on' || release == 'true' || release == '1',
    );
  }
}

class LockedDevice {
  const LockedDevice({required this.name, required this.host});
  final String name;
  final String host;
}
