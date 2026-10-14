import 'package:flutter/material.dart';

import '../../core/proto/messages.dart';
import '../../core/session/session.dart';
import 'icons.dart';
import 'ui_store.dart';

/// Gives the widget tree access to the store and the session actions without Riverpod in every widget.
class RenderScope extends InheritedWidget {
  const RenderScope({super.key, required this.store, required this.actions, required super.child});
  final UiStore store;
  final UiActions actions;

  static RenderScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<RenderScope>()!;

  @override
  bool updateShouldNotify(RenderScope old) => old.store != store || old.actions != actions;
}

extension RenderContext on BuildContext {
  UiStore get store => RenderScope.of(this).store;
  UiActions get actions => RenderScope.of(this).actions;
}

/// Rebuilds when a store key is emitted.
class StoreListener extends StatelessWidget {
  const StoreListener({super.key, required this.keyName, required this.builder});
  final String keyName;
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: context.store.listen(keyName), builder: (c, _) => builder(c));
}

/// Rebuilds with the current value of a widget id.
class ValueOf extends StatelessWidget {
  const ValueOf({super.key, required this.id, required this.builder});
  final String id;
  final Widget Function(BuildContext context, dynamic value) builder;
  @override
  Widget build(BuildContext context) {
    final store = context.store;
    return ListenableBuilder(listenable: store.listen('v:$id'), builder: (c, _) => builder(c, store.values[id]));
  }
}

Color? parseColor(String? s) {
  if (s == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(s)) return null;
  return Color(0xff000000 | int.parse(s.substring(1), radix: 16));
}

Color accentOf(BuildContext context, [String? s]) => parseColor(s) ?? Theme.of(context).colorScheme.primary;

/// Common chrome: label row (icon, label, value), hint on long press, disabled state, fixed height.
class Frame extends StatelessWidget {
  const Frame({super.key, required this.w, this.val, this.noLabel = false, required this.child});
  final WidgetDef w;
  final String? val;
  final bool noLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showLabel = !noLabel && (w.lbl != null || w.icon != null || val != null);
    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLabel)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                if (w.icon != null) ...[Icon(iconFor(w.icon), size: 16, color: theme.colorScheme.onSurfaceVariant), const SizedBox(width: 4)],
                if (w.lbl != null) Expanded(child: Text(w.lbl!, style: theme.textTheme.labelLarge, overflow: TextOverflow.ellipsis)),
                if (w.lbl == null) const Spacer(),
                if (val != null) Text(val!, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ),
        // sq squares the whole frame, so the content gets what the label leaves (no overflow for square content).
        if (w.sizeH != null) SizedBox(height: w.sizeH, child: child) else if (w.sq) Flexible(child: child) else child,
      ],
    );
    if (w.sq) body = AspectRatio(aspectRatio: 1, child: body);
    if (w.dis) body = Opacity(opacity: 0.5, child: IgnorePointer(child: body));
    body = Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: body);
    final hint = w.hint;
    if (hint == null) return body;
    return Tooltip(
      message: hint,
      triggerMode: TooltipTriggerMode.longPress,
      child: body,
    );
  }
}

/// Periodic rebuild (clock, dialog countdowns).
class Ticker extends StatefulWidget {
  const Ticker({super.key, this.period = const Duration(seconds: 1), required this.builder});
  final Duration period;
  final WidgetBuilder builder;
  @override
  State<Ticker> createState() => _TickerState();
}

class _TickerState extends State<Ticker> {
  late final Stream<void> _s = Stream.periodic(widget.period);
  @override
  Widget build(BuildContext context) => StreamBuilder<void>(stream: _s, builder: (c, _) => widget.builder(c));
}
