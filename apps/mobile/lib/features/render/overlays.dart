import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/session/session.dart';
import 'common.dart';
import 'ui_store.dart';

/// Transient non-blocking toasts stacked at the bottom; errors stay longer.
class ToastOverlay extends StatelessWidget {
  const ToastOverlay({super.key});
  @override
  Widget build(BuildContext context) => StoreListener(
        keyName: 'toast',
        builder: (c) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final t in c.store.toasts) _ToastItem(key: ValueKey(t.id), toast: t)],
        ),
      );
}

class _ToastItem extends StatefulWidget {
  const _ToastItem({super.key, required this.toast});
  final Toast toast;
  @override
  State<_ToastItem> createState() => _ToastItemState();
}

class _ToastItemState extends State<_ToastItem> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer(Duration(milliseconds: widget.toast.lvl == 'err' ? 7000 : 4000), () {
      if (mounted) context.store.removeToast(widget.toast.id);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = widget.toast;
    final (bg, fg, icon) = switch (t.lvl) {
      'err' => (cs.errorContainer, cs.onErrorContainer, Icons.error),
      'warn' => (cs.tertiaryContainer, cs.onTertiaryContainer, Icons.warning),
      _ => (cs.inverseSurface, cs.onInverseSurface, Icons.info),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Icon(icon, color: fg, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(t.msg, style: TextStyle(color: fg))),
            IconButton(icon: Icon(Icons.close, color: fg, size: 18), visualDensity: VisualDensity.compact, onPressed: () => context.store.removeToast(t.id)),
          ]),
        ),
      ),
    );
  }
}

/// Device dialogs: one at a time, oldest first; a timeout closes it as "cancel" (the device does the same).
class DialogHost extends StatefulWidget {
  const DialogHost({super.key, required this.child});
  final Widget child;
  @override
  State<DialogHost> createState() => _DialogHostState();
}

class _DialogHostState extends State<DialogHost> {
  String? _shown;
  late UiStore _store;
  late Listenable _l;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _store = context.store;
    _l = _store.listen('dlg');
    _l.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _l.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (!mounted) return;
    final d = _store.dialogs.isNotEmpty ? _store.dialogs.first : null;
    if (d == null || _shown != null) return;
    _shown = d.id;
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => DeviceDialogView(dialog: d, store: _store, actions: context.actions)).then((_) {
      _shown = null;
      _check();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class DeviceDialogView extends StatefulWidget {
  const DeviceDialogView({super.key, required this.dialog, required this.store, required this.actions});
  final DeviceDialog dialog;
  final UiStore store;
  final UiActions actions;
  @override
  State<DeviceDialogView> createState() => _DeviceDialogViewState();
}

class _DeviceDialogViewState extends State<DeviceDialogView> {
  late final _ctl = TextEditingController(text: widget.dialog.def ?? '');
  Timer? _tick;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.store.listen('dlg').addListener(_onStore);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_left <= 0) {
        _close();
      } else {
        setState(() {});
      }
    });
  }

  int get _left => (widget.dialog.at.add(Duration(seconds: widget.dialog.timeout)).difference(DateTime.now()).inMilliseconds / 1000).ceil().clamp(0, 1 << 30);

  void _onStore() {
    if (!widget.store.dialogs.any((d) => d.id == widget.dialog.id)) _close();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    widget.store.closeDialog(widget.dialog.id);
    if (mounted) Navigator.of(context).pop();
  }

  void _answer(bool ok) {
    if (_closed) return;
    _closed = true;
    widget.store.closeDialog(widget.dialog.id);
    widget.actions.dlg(widget.dialog.id, ok, widget.dialog.kind == 'prompt' ? _ctl.text : null);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    widget.store.listen('dlg').removeListener(_onStore);
    _tick?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dialog;
    return AlertDialog(
      title: Text(d.title ?? (d.kind == 'prompt' ? 'Input' : 'Confirm')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(d.msg),
        if (d.kind == 'prompt') ...[const SizedBox(height: 12), TextField(controller: _ctl, autofocus: true, onSubmitted: (_) => _answer(true), decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()))],
        const SizedBox(height: 8),
        Text('closes in $_left s', style: Theme.of(context).textTheme.bodySmall),
      ]),
      actions: [
        TextButton(onPressed: () => _answer(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => _answer(true), child: const Text('OK')),
      ],
    );
  }
}

/// Pairing: shown while the device wants a PIN or is locked out.
class PinDialog extends StatefulWidget {
  const PinDialog({super.key, required this.session, required this.deviceName});
  final Session session;
  final String deviceName;
  @override
  State<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<PinDialog> {
  final _ctl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
  }

  void _onSession() {
    if (!mounted) return;
    final s = widget.session;
    if (s.state != ConnState.pin && s.state != ConnState.locked) {
      Navigator.of(context).pop();
      return;
    }
    // Any session change while pairing is an auth result (wrong PIN, lockout, err 5): the field is editable again.
    setState(() => _busy = false);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_ctl.text.isEmpty || _busy) return;
    setState(() => _busy = true);
    widget.session.submitPin(_ctl.text);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final locked = s.state == ConnState.locked;
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(children: [const Icon(Icons.lock), const SizedBox(width: 8), Expanded(child: Text('${widget.deviceName} asks for a PIN'))]),
      content: locked
          ? Ticker(builder: (c) => Text('Too many wrong attempts. Locked for ${((s.lockUntil?.difference(DateTime.now()).inMilliseconds ?? 0) / 1000).ceil().clamp(0, 1 << 30)} s.', style: TextStyle(color: cs.error)))
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: _ctl,
                autofocus: true,
                obscureText: true,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'PIN', border: OutlineInputBorder()),
                onSubmitted: (_) => _submit(),
              ),
              if (s.authLeft != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Wrong PIN, ${s.authLeft} attempt${s.authLeft == 1 ? '' : 's'} left', style: TextStyle(color: cs.error))),
              const SizedBox(height: 8),
              Text('The PIN is set in the device sketch. It never leaves this phone.', style: Theme.of(context).textTheme.bodySmall),
            ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        if (!locked) FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Checking' : 'Pair')),
      ],
    );
  }
}
