import 'package:espface/core/session/session.dart';
import 'package:espface/core/session/token_store.dart';
import 'package:espface/features/render/common.dart';
import 'package:espface/features/render/overlays.dart';
import 'package:espface/features/render/ui_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';
import 'support/pump.dart';
import 'support/vectors.dart';

void main() {
  testWidgets('device confirm dialog answers and closes on device close', (t) async {
    final store = UiStore();
    final actions = RecordingActions();
    final h = Harness(store, actions);
    await t.pumpWidget(MaterialApp(home: RenderScope(store: store, actions: actions, child: const DialogHost(child: Scaffold(body: Text('ui'))))));
    h.apply(vectorMsg('dlg confirm'));
    await t.pumpAndSettle();
    expect(find.text('Shut down pump?'), findsOneWidget);
    expect(find.text('Pump'), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(actions.last('dlg'), ['d1', true, null]);
    expect(find.text('Shut down pump?'), findsNothing);

    h.apply(vectorMsg('dlg prompt with default and timeout'));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Kitchen boiler');
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(actions.last('dlg'), ['d2', true, 'Kitchen boiler']);

    h.apply(vectorMsg('dlg confirm'));
    await t.pumpAndSettle();
    expect(find.text('Shut down pump?'), findsOneWidget);
    h.apply(vectorMsg('dlg close'));
    await t.pumpAndSettle();
    expect(find.text('Shut down pump?'), findsNothing);
    expect(actions.calls.where((c) => c.$1 == 'dlg').length, 2, reason: 'device close does not answer');
    await unmount(t);
  });

  testWidgets('toasts appear and expire', (t) async {
    final store = UiStore();
    final actions = RecordingActions();
    await t.pumpWidget(MaterialApp(home: RenderScope(store: store, actions: actions, child: const Scaffold(body: ToastOverlay()))));
    store.addToast('warn', 'Overheating');
    await t.pump();
    expect(find.text('Overheating'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
    await t.pump();
    expect(find.text('Overheating'), findsNothing);
    await unmount(t);
  });

  testWidgets('pin dialog pairs via the session and shows attempts left / lockout', (t) async {
    late FakeTransport tr;
    final store = UiStore();
    final s = Session(transportFactory: () => tr = FakeTransport(), tokens: MemoryTokenStore(), store: store, deviceId: 'a1b2c3');
    s.start();
    await t.pump();
    tr.receive(vectorMsg('device hello pin required with nonce'));
    await t.pump();
    expect(s.state, ConnState.pin);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: PinDialog(session: s, deviceName: 'Boiler'))));
    expect(find.text('Boiler asks for a PIN'), findsOneWidget);
    await t.enterText(find.byType(TextField), '1234');
    await t.tap(find.text('Pair'));
    await t.pump();
    expect(tr.last('auth'), isNotNull);
    tr.receive(vectorMsg('device auth wrong with attempts left'));
    await t.pump();
    await t.pump();
    expect(find.text('Wrong PIN, 3 attempts left'), findsOneWidget);
    tr.receive(vectorMsg('device auth locked'));
    await t.pump();
    await t.pump();
    expect(find.textContaining('Locked for'), findsOneWidget);
    await unmount(t);
    s.dispose();
  });
}
