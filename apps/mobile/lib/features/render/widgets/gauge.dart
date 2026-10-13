import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/proto/messages.dart';
import '../../../core/proto/values.dart';
import '../common.dart';

class GaugeWidget extends StatelessWidget {
  const GaugeWidget(this.w, {super.key});
  final WidgetDef w;

  @override
  Widget build(BuildContext context) => ValueOf(
        id: w.id,
        builder: (c, raw) {
          final min = w.min, max = w.max;
          final v = asNum(raw, min);
          final frac = max > min ? clampNum((v - min) / (max - min), 0, 1) : 0.0;
          final zones = w.zones;
          GaugeZone? zone;
          for (final z in zones) {
            if (v >= z.from && v <= z.to) zone = z;
          }
          final color = parseColor(zone?.color) ?? accentOf(c, w.color);
          final text = fmtValue(raw, w.fmt);
          final cs = Theme.of(c).colorScheme;
          final style = w.style ?? 'arc';
          if (style == 'linear') {
            double pct(double x) => max > min ? clampNum((x - min) / (max - min), 0, 1) : 0;
            return Frame(
              w: w,
              val: text + (w.unit != null ? ' ${w.unit}' : ''),
              child: SizedBox(
                height: 12,
                child: LayoutBuilder(
                  builder: (c, box) => Stack(children: [
                    Container(decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(6))),
                    for (final z in zones)
                      Positioned(left: pct(z.from) * box.maxWidth, width: (pct(z.to) - pct(z.from)) * box.maxWidth, top: 0, bottom: 0, child: Container(color: parseColor(z.color)?.withValues(alpha: 0.35))),
                    Positioned(left: 0, width: frac * box.maxWidth, top: 0, bottom: 0, child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)))),
                    Positioned(left: frac * box.maxWidth - 1, width: 2, top: 0, bottom: 0, child: Container(color: cs.onSurface)),
                  ]),
                ),
              ),
            );
          }
          final round = style == 'round';
          return Frame(
            w: w,
            child: Center(
              child: SizedBox(
                width: 200,
                height: round ? 200 : 172,
                child: CustomPaint(
                  painter: _GaugePainter(frac: frac, zones: zones, min: min, max: max, round: round, color: color, track: cs.surfaceContainerHighest),
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: round ? 0 : 30),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(text, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()])),
                        if (w.unit != null) Text(w.unit!, style: TextStyle(color: cs.onSurfaceVariant)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.frac, required this.zones, required this.min, required this.max, required this.round, required this.color, required this.track});
  final double frac;
  final List<GaugeZone> zones;
  final double min, max;
  final bool round;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final start = round ? -math.pi / 2 : math.pi * 0.75;
    final sweep = round ? math.pi * 2 : math.pi * 1.5;
    final r = size.width / 2 - 10;
    final center = Offset(size.width / 2, round ? size.height / 2 : size.width / 2);
    final rect = Rect.fromCircle(center: center, radius: r);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, round ? sweep - 0.001 : sweep, false, p..color = track);
    double ang(double x) => max > min ? clampNum((x - min) / (max - min), 0, 1) * sweep : 0;
    for (final z in zones) {
      final c = parseColor(z.color);
      if (c == null) continue;
      canvas.drawArc(rect, start + ang(z.from), ang(z.to) - ang(z.from), false, p..color = c.withValues(alpha: 0.35)..strokeCap = StrokeCap.butt);
    }
    if (frac > 0) canvas.drawArc(rect, start, frac * sweep, false, p..color = color..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_GaugePainter o) => o.frac != frac || o.color != color || o.round != round || o.zones != zones || o.track != track;
}
