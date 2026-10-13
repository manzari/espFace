import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nsd/nsd.dart' as nsd;

import '../../app/providers.dart';
import 'device.dart';

/// mDNS browse for `_espface._tcp` while the add sheet is open; TXT id/name/v/proj/icon fill the entry.
class DiscoveryNotifier extends Notifier<List<DiscoveredDevice>> {
  nsd.Discovery? _d;
  String? error;

  @override
  List<DiscoveredDevice> build() {
    ref.onDispose(_stop);
    _start();
    return const [];
  }

  Future<void> _start() async {
    try {
      final d = await nsd.startDiscovery('_espface._tcp', ipLookupType: nsd.IpLookupType.v4);
      _d = d;
      d.addServiceListener((s, status) => _refresh());
      _refresh();
    } catch (e) {
      error = e.toString();
      state = const [];
    }
  }

  void _refresh() {
    final d = _d;
    if (d == null) return;
    final filter = ref.read(flavorProvider).proj;
    final out = <DiscoveredDevice>[];
    for (final s in d.services) {
      final dev = fromService(s.name, s.host, s.port, s.txt, addresses: s.addresses?.map((a) => a.address).toList());
      if (dev == null) continue;
      if (filter != null && dev.proj != filter) continue;
      out.add(dev);
    }
    state = out;
  }

  Future<void> _stop() async {
    final d = _d;
    _d = null;
    if (d != null) {
      try {
        await nsd.stopDiscovery(d);
      } catch (_) {}
    }
  }

  static String _txt(Map<String, List<int>?>? txt, String k) {
    final v = txt?[k];
    return v == null ? '' : utf8.decode(v, allowMalformed: true);
  }

  /// Pure mapping used by tests; an entry without a resolvable host is skipped.
  static DiscoveredDevice? fromService(String? name, String? host, int? port, Map<String, List<int>?>? txt, {List<String>? addresses}) {
    final h = (addresses != null && addresses.isNotEmpty) ? addresses.first : host;
    if (h == null || h.isEmpty) return null;
    final hp = port != null && port != 80 ? '${h.replaceAll(RegExp(r'\.$'), '')}:$port' : h.replaceAll(RegExp(r'\.$'), '');
    final id = _txt(txt, 'id');
    final n = _txt(txt, 'name');
    final proj = _txt(txt, 'proj');
    final icon = _txt(txt, 'icon');
    return DiscoveredDevice(
      id: id,
      name: n.isNotEmpty ? n : (name ?? hp),
      host: hp,
      proj: proj.isEmpty ? null : proj,
      icon: icon.isEmpty ? null : icon,
      v: int.tryParse(_txt(txt, 'v')),
    );
  }
}

final discoveryProvider = NotifierProvider.autoDispose<DiscoveryNotifier, List<DiscoveredDevice>>(DiscoveryNotifier.new);
