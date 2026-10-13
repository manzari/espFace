import 'dart:convert';

import 'package:espface/core/proto/codec.dart';
import 'package:espface/features/render/common.dart';
import 'package:espface/features/render/ui_store.dart';
import 'package:espface/features/render/widgets/registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_transport.dart';

class Harness {
  Harness(this.store, this.actions);
  final UiStore store;
  final RecordingActions actions;
  void apply(Map<String, dynamic> m) => store.apply(decode(jsonEncode(m))!);
  void upd(String id, dynamic v) => apply({'t': 'upd', 'v': {id: v}});
}

Widget scoped(UiStore store, RecordingActions actions, Widget child) => MaterialApp(
      home: Scaffold(body: RenderScope(store: store, actions: actions, child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(8), child: child)))),
    );

/// Renders one widget definition (plus optional extra widgets) with a recording action sink.
Future<Harness> pumpWidgetDef(WidgetTester tester, Map<String, dynamic> def, {dynamic value, List<Map<String, dynamic>> extra = const []}) async {
  final store = UiStore();
  final actions = RecordingActions();
  final h = Harness(store, actions);
  h.apply({'t': 'ui', 'rev': 1, 'w': [...extra, def]});
  if (value != null) h.upd(def['id'] as String, value);
  await tester.pumpWidget(scoped(store, actions, WidgetView(def['id'] as String)));
  await tester.pump();
  return h;
}

/// Disposes the tree so periodic timers (clock, dialogs, toasts) do not leak past the test.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}
