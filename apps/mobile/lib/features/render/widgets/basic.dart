import 'package:flutter/material.dart';

import '../../../core/proto/messages.dart';
import '../../../core/proto/values.dart';
import '../common.dart';
import '../icons.dart';

class LabelWidget extends StatelessWidget {
  const LabelWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  Widget build(BuildContext context) => Frame(
        w: w,
        child: ValueOf(
          id: w.id,
          builder: (c, v) => Text.rich(TextSpan(children: [
            TextSpan(text: fmtValue(v, w.fmt), style: Theme.of(c).textTheme.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            if (w.unit != null && v is num) TextSpan(text: ' ${w.unit}', style: Theme.of(c).textTheme.bodySmall),
          ])),
        ),
      );
}

class HeaderWidget extends StatelessWidget {
  const HeaderWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  Widget build(BuildContext context) => Frame(
        w: w,
        noLabel: true,
        child: Row(children: [
          if (w.icon != null) ...[Icon(iconFor(w.icon), size: 22), const SizedBox(width: 6)],
          Expanded(child: Text(w.lbl ?? '', style: Theme.of(context).textTheme.titleLarge)),
        ]),
      );
}

class TextblockWidget extends StatelessWidget {
  const TextblockWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  Widget build(BuildContext context) => Frame(w: w, child: Text(w.text ?? '', style: Theme.of(context).textTheme.bodyMedium));
}

class SpacerWidget extends StatelessWidget {
  const SpacerWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  Widget build(BuildContext context) => SizedBox(height: w.sizeH ?? 16);
}

class UnsupportedWidget extends StatelessWidget {
  const UnsupportedWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant), borderRadius: BorderRadius.circular(8)),
        child: Text('unsupported widget "${w.ty}"${w.lbl != null ? ' (${w.lbl})' : ''}', style: TextStyle(color: cs.onSurfaceVariant, fontStyle: FontStyle.italic)),
      ),
    );
  }
}

class LedWidget extends StatelessWidget {
  const LedWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  Widget build(BuildContext context) => Frame(
        w: w,
        noLabel: true,
        child: ValueOf(
          id: w.id,
          builder: (c, v) {
            final on = w.rgb ? asNum(v) > 0 : (v == true || (v is num && v != 0));
            final color = w.rgb ? parseColor(hexColor(asNum(v)))! : accentOf(c, w.color);
            final cs = Theme.of(c).colorScheme;
            return Row(children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? color : cs.surfaceContainerHighest,
                  border: Border.all(color: on ? color : cs.outlineVariant),
                  boxShadow: on ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)] : null,
                ),
              ),
              const SizedBox(width: 8),
              if (w.icon != null) ...[Icon(iconFor(w.icon), size: 18), const SizedBox(width: 4)],
              if (w.lbl != null) Expanded(child: Text(w.lbl!)),
            ]);
          },
        ),
      );
}

/// Seven-segment style readout: fixed digit count, ghost "8"s behind the value.
class DisplayWidget extends StatelessWidget {
  const DisplayWidget(this.w, {super.key});
  final WidgetDef w;

  static String format(dynamic v, int digits) {
    var s = asStr(v);
    if (v is num) {
      s = v is int || v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed((digits - v.truncate().toString().length - 1).clamp(0, 10));
    }
    final width = digits + (s.contains('.') ? 1 : 0);
    return s.length > width ? s.substring(0, width) : s.padLeft(width);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(fontFamily: 'monospace', fontSize: 30, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]);
    return Frame(
      w: w,
      child: ValueOf(
        id: w.id,
        builder: (c, v) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Stack(alignment: Alignment.centerRight, children: [
              Text('8' * w.digits, style: style.copyWith(color: cs.onSurface.withValues(alpha: 0.08))),
              Text(format(v, w.digits), style: style.copyWith(color: cs.primary)),
            ]),
            if (w.unit != null) ...[const SizedBox(width: 6), Text(w.unit!, style: TextStyle(color: cs.onSurfaceVariant))],
          ]),
        ),
      ),
    );
  }
}

class ProgressWidget extends StatelessWidget {
  const ProgressWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  Widget build(BuildContext context) => ValueOf(
        id: w.id,
        builder: (c, raw) {
          final min = w.min, max = w.max;
          final v = asNum(raw, min);
          double pct(double x) => max > min ? clampNum((x - min) / (max - min), 0, 1) : 0;
          double left, width;
          if (w.center == true) {
            final mid = pct((min + max) / 2), p = pct(v);
            left = p < mid ? p : mid;
            width = (p - mid).abs();
          } else {
            left = 0;
            width = pct(v);
          }
          final cs = Theme.of(c).colorScheme;
          final color = accentOf(c, w.color);
          return Frame(
            w: w,
            val: fmtValue(raw, w.fmt) + (w.unit != null ? ' ${w.unit}' : ''),
            child: SizedBox(
              height: 10,
              child: LayoutBuilder(
                builder: (c, box) => Stack(children: [
                  Container(decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(5))),
                  Positioned(
                    left: left * box.maxWidth,
                    width: width * box.maxWidth,
                    top: 0,
                    bottom: 0,
                    child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5))),
                  ),
                  if (w.center == true) Positioned(left: box.maxWidth / 2 - 1, width: 2, top: 0, bottom: 0, child: Container(color: cs.onSurfaceVariant)),
                ]),
              ),
            ),
          );
        },
      );
}

class SwitchWidget extends StatelessWidget {
  const SwitchWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  Widget build(BuildContext context) => Frame(
        w: w,
        noLabel: true,
        child: ValueOf(
          id: w.id,
          builder: (c, v) {
            final on = v == true;
            final state = on ? w.on : w.off;
            final color = parseColor(w.color);
            return Row(children: [
              Switch(
                value: on,
                activeTrackColor: color,
                onChanged: w.readOnly ? null : (x) => c.actions.set(w.id, x),
              ),
              const SizedBox(width: 8),
              if (w.icon != null) ...[Icon(iconFor(w.icon), size: 18), const SizedBox(width: 4)],
              if (w.lbl != null) Expanded(child: Text(w.lbl!, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (w.lbl == null) const Spacer(),
              if (state != null) Text(state, style: Theme.of(c).textTheme.labelMedium?.copyWith(color: Theme.of(c).colorScheme.onSurfaceVariant)),
            ]);
          },
        ),
      );
}

class ButtonWidget extends StatefulWidget {
  const ButtonWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  State<ButtonWidget> createState() => _ButtonWidgetState();
}

class _ButtonWidgetState extends State<ButtonWidget> {
  bool _held = false;

  void _press() {
    if (!widget.w.hold || _held || widget.w.readOnly) return;
    setState(() => _held = true);
    context.actions.ev(widget.w.id, 1);
  }

  void _release() {
    if (!widget.w.hold || !_held) return;
    setState(() => _held = false);
    context.actions.ev(widget.w.id, 0);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final color = parseColor(w.color);
    final style = FilledButton.styleFrom(
      backgroundColor: _held ? (color ?? Theme.of(context).colorScheme.primary).withValues(alpha: 0.7) : color,
      foregroundColor: color != null ? Colors.white : null,
    );
    final child = Row(mainAxisSize: MainAxisSize.min, children: [
      if (w.icon != null) ...[Icon(iconFor(w.icon), size: 18), const SizedBox(width: 6)],
      Flexible(child: Text(w.lbl ?? w.id, overflow: TextOverflow.ellipsis)),
    ]);
    final btn = w.hold
        ? Listener(
            onPointerDown: (_) => _press(),
            onPointerUp: (_) => _release(),
            onPointerCancel: (_) => _release(),
            child: FilledButton(style: style, onPressed: w.readOnly ? null : () {}, child: child),
          )
        : FilledButton(style: style, onPressed: w.readOnly ? null : () => context.actions.ev(w.id), child: child);
    return Frame(w: w, noLabel: true, child: btn);
  }
}

class DpadWidget extends StatefulWidget {
  const DpadWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  State<DpadWidget> createState() => _DpadWidgetState();
}

class _DpadWidgetState extends State<DpadWidget> {
  String? _held;

  void _press(String d) {
    if (_held != null || widget.w.readOnly) return;
    _held = d;
    context.actions.ev(widget.w.id, d);
  }

  void _release() {
    if (_held == null) return;
    _held = null;
    context.actions.ev(widget.w.id, 0);
  }

  Widget _key(String d, IconData icon) => Listener(
        onPointerDown: (_) => _press(d),
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: SizedBox(
          width: 52,
          height: 52,
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: widget.w.readOnly ? null : () {},
            child: Icon(icon, semanticLabel: d),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(width: 6, height: 6);
    return Frame(
      w: widget.w,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _key('u', Icons.keyboard_arrow_up),
          gap,
          Row(mainAxisSize: MainAxisSize.min, children: [_key('l', Icons.keyboard_arrow_left), gap, _key('c', Icons.circle), gap, _key('r', Icons.keyboard_arrow_right)]),
          gap,
          _key('d', Icons.keyboard_arrow_down),
        ]),
      ),
    );
  }
}
