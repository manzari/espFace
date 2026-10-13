import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/proto/messages.dart';
import '../../../core/proto/values.dart';
import '../common.dart';

/// Keeps a local copy of the remote value that follows it until the user edits.
mixin _LocalValue<T, W extends StatefulWidget> on State<W> {
  T? _local;
  dynamic _lastRemote;
  T localOf(dynamic remote, T Function(dynamic) conv) {
    if (_local == null || _lastRemote != remote) {
      _lastRemote = remote;
      _local = conv(remote);
    }
    return _local as T;
  }

  void setLocal(T v) => setState(() => _local = v);
}

class SliderWidget extends StatefulWidget {
  const SliderWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  State<SliderWidget> createState() => _SliderWidgetState();
}

class _SliderWidgetState extends State<SliderWidget> with _LocalValue<double, SliderWidget> {
  Timer? _t;

  void _emit(double x, bool now) {
    setLocal(x);
    _t?.cancel();
    if (now) {
      _t = null;
      context.actions.set(widget.w.id, _round(x));
    } else {
      _t = Timer(const Duration(milliseconds: 120), () {
        _t = null;
        if (mounted) context.actions.set(widget.w.id, _round(x));
      });
    }
  }

  num _round(double x) {
    final d = decimals(widget.w.step);
    return d == 0 ? x.round() : double.parse(x.toStringAsFixed(d));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    return ValueOf(
      id: w.id,
      builder: (c, remote) {
        final min = w.min, max = w.max > w.min ? w.max : w.min + 1;
        final v = clampNum(localOf(remote, (r) => asNum(r, min)), min, max);
        final text = v.toStringAsFixed(decimals(w.step)) + (w.unit != null ? ' ${w.unit}' : '');
        final divisions = ((max - min) / w.step).round();
        return Frame(
          w: w,
          val: text,
          child: SliderTheme(
            data: SliderTheme.of(c).copyWith(activeTrackColor: parseColor(w.color), thumbColor: parseColor(w.color)),
            child: Slider(
              value: v,
              min: min,
              max: max,
              divisions: divisions > 0 && divisions <= 10000 ? divisions : null,
              onChanged: w.readOnly ? null : (x) => _emit(x, false),
              onChangeEnd: w.readOnly ? null : (x) => _emit(x, true),
            ),
          ),
        );
      },
    );
  }
}

class NumberWidget extends StatefulWidget {
  const NumberWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  State<NumberWidget> createState() => _NumberWidgetState();
}

class _NumberWidgetState extends State<NumberWidget> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  double _remote = 0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit(double.tryParse(_ctl.text) ?? _remote);
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit(double x) {
    final w = widget.w;
    final c = double.parse(clampNum(x, w.min, w.max).toStringAsFixed(decimals(w.step)));
    _ctl.text = fmtValue(c);
    if (c != _remote) context.actions.set(w.id, decimals(w.step) == 0 ? c.round() : c);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    return ValueOf(
      id: w.id,
      builder: (c, raw) {
        final r = asNum(raw, w.min);
        if (r != _remote || (!_focus.hasFocus && _ctl.text.isEmpty)) {
          _remote = r;
          if (!_focus.hasFocus) _ctl.text = fmtValue(r);
        }
        return Frame(
          w: w,
          child: Row(children: [
            if (w.spin) IconButton.filledTonal(onPressed: w.readOnly ? null : () => _commit(_remote - w.step), icon: const Icon(Icons.remove)),
            Expanded(
              child: TextField(
                controller: _ctl,
                focusNode: _focus,
                enabled: !w.readOnly,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                textAlign: w.spin ? TextAlign.center : TextAlign.start,
                decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), suffixText: w.unit),
                onSubmitted: (s) => _commit(double.tryParse(s) ?? _remote),
              ),
            ),
            if (w.spin) IconButton.filledTonal(onPressed: w.readOnly ? null : () => _commit(_remote + w.step), icon: const Icon(Icons.add)),
          ]),
        );
      },
    );
  }
}

class TextWidget extends StatefulWidget {
  const TextWidget(this.w, {super.key, this.multiline = false});
  final WidgetDef w;
  final bool multiline;
  @override
  State<TextWidget> createState() => _TextWidgetState();
}

class _TextWidgetState extends State<TextWidget> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  String _remote = '';
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _ok {
    final re = widget.w.re;
    if (re == null) return true;
    try {
      return RegExp(re).hasMatch(_ctl.text);
    } catch (_) {
      return true;
    }
  }

  void _commit() {
    if (_ok && _ctl.text != _remote) context.actions.set(widget.w.id, _ctl.text);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    return ValueOf(
      id: w.id,
      builder: (c, raw) {
        final r = asStr(raw);
        if (r != _remote) {
          _remote = r;
          if (!_focus.hasFocus) _ctl.text = r;
        }
        return Frame(
          w: w,
          child: TextField(
            controller: _ctl,
            focusNode: _focus,
            enabled: !w.readOnly,
            obscureText: w.secret && !_show,
            maxLength: w.maxlen,
            maxLines: widget.multiline ? w.rows : 1,
            minLines: widget.multiline ? w.rows : null,
            autocorrect: !w.secret,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _commit(),
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              counterText: '',
              errorText: _ok ? null : 'Does not match ${w.re}',
              suffixIcon: w.secret ? IconButton(icon: Icon(_show ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _show = !_show)) : null,
            ),
          ),
        );
      },
    );
  }
}

class SelectWidget extends StatelessWidget {
  const SelectWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  Widget build(BuildContext context) => ValueOf(
        id: w.id,
        builder: (c, raw) {
          final opts = w.opts;
          final v = asNum(raw).round();
          void pick(int i) {
            if (i != v) c.actions.set(w.id, i);
          }

          if (opts.isEmpty) return Frame(w: w, child: const Text('no options'));
          if (w.style == 'seg') {
            return Frame(
              w: w,
              child: SegmentedButton<int>(
                segments: [for (var i = 0; i < opts.length; i++) ButtonSegment(value: i, label: Text(opts[i]))],
                selected: {v.clamp(0, opts.length - 1)},
                showSelectedIcon: false,
                onSelectionChanged: w.readOnly ? null : (s) => pick(s.first),
              ),
            );
          }
          return Frame(
            w: w,
            child: DropdownButtonFormField<int>(
              initialValue: v >= 0 && v < opts.length ? v : 0,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              items: [for (var i = 0; i < opts.length; i++) DropdownMenuItem(value: i, child: Text(opts[i]))],
              onChanged: w.readOnly ? null : (i) => i != null ? pick(i) : null,
            ),
          );
        },
      );
}

class FlagsWidget extends StatelessWidget {
  const FlagsWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  Widget build(BuildContext context) => ValueOf(
        id: w.id,
        builder: (c, raw) {
          final opts = w.opts.take(32).toList();
          final v = asNum(raw).round() & 0xffffffff;
          return Frame(
            w: w,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < opts.length; i++)
                  FilterChip(
                    label: Text(opts[i]),
                    selected: (v & (1 << i)) != 0,
                    onSelected: w.readOnly ? null : (_) => c.actions.set(w.id, (v ^ (1 << i)) & 0xffffffff),
                  ),
              ],
            ),
          );
        },
      );
}

class ColorWidget extends StatelessWidget {
  const ColorWidget(this.w, {super.key});
  final WidgetDef w;

  Future<void> _pick(BuildContext context, int current) async {
    final picked = await showDialog<int>(context: context, builder: (_) => ColorPickerDialog(initial: current));
    if (picked != null && context.mounted) context.actions.set(w.id, picked);
  }

  @override
  Widget build(BuildContext context) => ValueOf(
        id: w.id,
        builder: (c, raw) {
          final n = asNum(raw).round().clamp(0, 0xffffff);
          final hex = hexColor(n);
          return Frame(
            w: w,
            val: hex,
            child: InkWell(
              onTap: w.readOnly ? null : () => _pick(c, n),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 36,
                decoration: BoxDecoration(color: parseColor(hex), borderRadius: BorderRadius.circular(8), border: Border.all(color: Theme.of(c).colorScheme.outlineVariant)),
              ),
            ),
          );
        },
      );
}

/// Minimal RGB picker (sliders + hex field); avoids an extra dependency.
class ColorPickerDialog extends StatefulWidget {
  const ColorPickerDialog({super.key, required this.initial});
  final int initial;
  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late int _v = widget.initial;
  late final _hex = TextEditingController(text: hexColor(widget.initial).substring(1));

  int get _r => (_v >> 16) & 0xff;
  int get _g => (_v >> 8) & 0xff;
  int get _b => _v & 0xff;

  void _set(int r, int g, int b) => setState(() {
        _v = (r << 16) | (g << 8) | b;
        _hex.text = hexColor(_v).substring(1);
      });

  Widget _slider(String l, int v, Color c, void Function(int) on) => Row(children: [
        SizedBox(width: 16, child: Text(l)),
        Expanded(child: Slider(value: v.toDouble(), min: 0, max: 255, activeColor: c, onChanged: (x) => on(x.round()))),
        SizedBox(width: 32, child: Text('$v', textAlign: TextAlign.right)),
      ]);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Color'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(height: 40, decoration: BoxDecoration(color: Color(0xff000000 | _v), borderRadius: BorderRadius.circular(8))),
          const SizedBox(height: 8),
          _slider('R', _r, Colors.red, (x) => _set(x, _g, _b)),
          _slider('G', _g, Colors.green, (x) => _set(_r, x, _b)),
          _slider('B', _b, Colors.blue, (x) => _set(_r, _g, x)),
          TextField(
            controller: _hex,
            decoration: const InputDecoration(prefixText: '#', isDense: true, border: OutlineInputBorder()),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')), LengthLimitingTextInputFormatter(6)],
            onChanged: (s) {
              if (s.length == 6) setState(() => _v = int.parse(s, radix: 16));
            },
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, _v), child: const Text('OK')),
        ],
      );
}

/// Values are unix seconds in local time; mode "time" counts seconds since local midnight.
class DatetimeWidget extends StatelessWidget {
  const DatetimeWidget(this.w, {super.key});
  final WidgetDef w;

  static String format(String mode, int unix) {
    if (mode == 'time') return '${pad2((unix ~/ 3600) % 24)}:${pad2((unix ~/ 60) % 60)}';
    final d = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
    final date = '${d.year}-${pad2(d.month)}-${pad2(d.day)}';
    return mode == 'date' ? date : '$date ${pad2(d.hour)}:${pad2(d.minute)}';
  }

  Future<void> _pick(BuildContext context, int unix) async {
    final mode = w.mode;
    if (mode == 'time') {
      final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: (unix ~/ 3600) % 24, minute: (unix ~/ 60) % 60));
      if (t != null && context.mounted) context.actions.set(w.id, t.hour * 3600 + t.minute * 60);
      return;
    }
    final cur = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
    final d = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(1970), lastDate: DateTime(2100));
    if (d == null || !context.mounted) return;
    if (mode == 'date') {
      context.actions.set(w.id, DateTime(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 1000);
      return;
    }
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: cur.hour, minute: cur.minute));
    if (t == null || !context.mounted) return;
    context.actions.set(w.id, DateTime(d.year, d.month, d.day, t.hour, t.minute).millisecondsSinceEpoch ~/ 1000);
  }

  @override
  Widget build(BuildContext context) => ValueOf(
        id: w.id,
        builder: (c, raw) {
          final unix = asNum(raw).round();
          return Frame(
            w: w,
            child: OutlinedButton.icon(
              onPressed: w.readOnly ? null : () => _pick(c, unix),
              icon: Icon(w.mode == 'time' ? Icons.schedule : Icons.calendar_month),
              label: Align(alignment: Alignment.centerLeft, child: Text(format(w.mode, unix))),
            ),
          );
        },
      );
}
