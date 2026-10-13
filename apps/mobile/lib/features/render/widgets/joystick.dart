import 'package:flutter/material.dart';

import '../../../core/proto/messages.dart';
import '../../../core/proto/values.dart';
import '../common.dart';

/// x right, y up, -100..100; `exp` applies a squared curve for fine control; `center` auto-returns on release.
class JoystickWidget extends StatefulWidget {
  const JoystickWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  State<JoystickWidget> createState() => _JoystickWidgetState();
}

class _JoystickWidgetState extends State<JoystickWidget> {
  Offset? _local;
  dynamic _lastRemote;
  DateTime _lastSend = DateTime.fromMillisecondsSinceEpoch(0);
  bool _active = false;

  Offset _remote(dynamic raw) {
    if (raw is List && raw.length == 2) return Offset(asNum(raw[0]), asNum(raw[1]));
    return Offset.zero;
  }

  int _curve(double v) => widget.w.exp ? (v.sign * v * v / 100).round() : v.round();

  void _send(Offset p, bool force) {
    final now = DateTime.now();
    if (!force && now.difference(_lastSend).inMilliseconds < 50) return;
    _lastSend = now;
    context.actions.set(widget.w.id, [_curve(p.dx), _curve(p.dy)]);
  }

  void _update(Offset pos, Size size, bool force) {
    final x = clampNum(pos.dx / size.width * 200 - 100, -100, 100);
    final y = clampNum(100 - pos.dy / size.height * 200, -100, 100);
    final p = Offset(x.roundToDouble(), y.roundToDouble());
    setState(() => _local = p);
    _send(p, force);
  }

  void _end(Offset? pos, Size size) {
    if (!_active) return;
    _active = false;
    if (widget.w.center != false) {
      setState(() => _local = Offset.zero);
      context.actions.set(widget.w.id, [0, 0]);
    } else if (pos != null) {
      _update(pos, size, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    return ValueOf(
      id: w.id,
      builder: (c, raw) {
        if (_lastRemote != raw) {
          _lastRemote = raw;
          _local = _remote(raw);
        }
        final pos = _local ?? Offset.zero;
        final cs = Theme.of(c).colorScheme;
        return Frame(
          w: w,
          val: '${pos.dx.round()}, ${pos.dy.round()}',
          child: AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (c, box) {
                final size = Size(box.maxWidth, box.maxHeight);
                return Listener(
                  key: ValueKey('joy:${w.id}'),
                  onPointerDown: w.readOnly
                      ? null
                      : (e) {
                          _active = true;
                          _update(e.localPosition, size, true);
                        },
                  onPointerMove: w.readOnly ? null : (e) => _active ? _update(e.localPosition, size, false) : null,
                  onPointerUp: (e) => _end(e.localPosition, size),
                  onPointerCancel: (e) => _end(null, size),
                  child: Container(
                    decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant)),
                    child: Stack(children: [
                      Positioned(left: 0, right: 0, top: size.height / 2, child: Container(height: 1, color: cs.outlineVariant)),
                      Positioned(top: 0, bottom: 0, left: size.width / 2, child: Container(width: 1, color: cs.outlineVariant)),
                      Positioned(
                        left: (50 + pos.dx / 2) / 100 * size.width - 18,
                        top: (50 - pos.dy / 2) / 100 * size.height - 18,
                        child: Container(width: 36, height: 36, decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary, boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)])),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
