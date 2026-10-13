import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/proto/messages.dart';
import 'device.dart';

const _key = 'espface.devices';

/// Saved device list in shared_preferences (tokens live in the secure token store). Locked flavors seed it and freeze edits.
class DevicesNotifier extends Notifier<List<SavedDevice>> {
  @override
  List<SavedDevice> build() {
    final flavor = ref.watch(flavorProvider);
    if (flavor.locked) {
      return [
        for (var i = 0; i < flavor.lockedDevices.length; i++)
          SavedDevice(key: SavedDevice.keyFor(host: flavor.lockedDevices[i].host), host: flavor.lockedDevices[i].host, name: flavor.lockedDevices[i].name, proj: flavor.proj, order: i),
      ];
    }
    final raw = ref.watch(prefsProvider).getString(_key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).map(SavedDevice.fromJson).whereType<SavedDevice>().toList();
    } catch (_) {
      return const [];
    }
  }

  bool get locked => ref.read(flavorProvider).locked;

  void _save(List<SavedDevice> list) {
    state = list;
    if (!locked) ref.read(prefsProvider).setString(_key, jsonEncode(list.map((d) => d.toJson()).toList()));
  }

  SavedDevice? byKey(String key) {
    for (final d in state) {
      if (d.key == key) return d;
    }
    return null;
  }

  /// Adds or updates (same key) and returns the stored record.
  SavedDevice upsert(SavedDevice d) {
    if (locked) return byKey(d.key) ?? d;
    final i = state.indexWhere((x) => x.key == d.key);
    if (i >= 0) {
      final n = [...state];
      n[i] = d.copyWith(order: state[i].order);
      _save(n);
      return n[i];
    }
    final order = state.where((x) => x.group == d.group).fold<int>(-1, (a, x) => x.order > a ? x.order : a) + 1;
    final rec = d.copyWith(order: order);
    _save([...state, rec]);
    return rec;
  }

  SavedDevice addDiscovered(DiscoveredDevice d) => upsert(SavedDevice(
        key: SavedDevice.keyFor(id: d.id, host: d.host),
        host: d.host,
        id: d.id.isEmpty ? null : d.id,
        name: d.name,
        proj: d.proj,
        icon: d.icon,
      ));

  SavedDevice addManual(String host) => upsert(SavedDevice(key: SavedDevice.keyFor(host: host), host: host, name: host));

  void remove(String key) {
    if (locked) return;
    _save(state.where((d) => d.key != key).toList());
  }

  /// Updates name/proj/icon/fw from the device hello (host stays).
  void learn(String key, HelloMsg h) {
    final i = state.indexWhere((x) => x.key == key);
    if (i < 0) return;
    final cur = state[i];
    final next = cur.learn(h);
    if (next.id == cur.id && next.name == cur.name && next.proj == cur.proj && next.icon == cur.icon && next.fw == cur.fw) return;
    final n = [...state];
    n[i] = next;
    _save(n);
  }

  /// Groups by `proj` in first-seen order, devices sorted by `order`; applies the flavor's fixed project filter.
  List<(String, List<SavedDevice>)> grouped() {
    final filter = ref.read(flavorProvider).proj;
    final groups = <String, List<SavedDevice>>{};
    for (final d in state) {
      if (filter != null && d.group != filter) continue;
      groups.putIfAbsent(d.group, () => []).add(d);
    }
    for (final g in groups.values) {
      g.sort((a, b) => a.order.compareTo(b.order));
    }
    return [for (final e in groups.entries) (e.key, e.value)];
  }

  /// `newIndex` is the position after removal (ReorderableListView.onReorderItem semantics).
  void reorder(String group, int oldIndex, int newIndex) {
    if (locked) return;
    final items = state.where((d) => d.group == group).toList()..sort((a, b) => a.order.compareTo(b.order));
    if (oldIndex < 0 || oldIndex >= items.length) return;
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex.clamp(0, items.length), moved);
    final orders = {for (var i = 0; i < items.length; i++) items[i].key: i};
    _save([for (final d in state) orders.containsKey(d.key) ? d.copyWith(order: orders[d.key]) : d]);
  }
}

final devicesProvider = NotifierProvider<DevicesNotifier, List<SavedDevice>>(DevicesNotifier.new);
