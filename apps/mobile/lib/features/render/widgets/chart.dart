import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/proto/messages.dart';
import '../../../core/proto/values.dart';
import '../common.dart';

const _palette = [Color(0xff2f7df6), Color(0xffff8800), Color(0xff1f9d55), Color(0xffd9342b), Color(0xff8e44ad), Color(0xff16a085), Color(0xffc77700), Color(0xff7f8c8d)];

Color seriesColor(ChartSeries s, int i) => parseColor(s.color) ?? _palette[i % _palette.length];

/// Line/area/bar chart over the store's per-series ring buffers (ms epoch timestamps).
class ChartWidget extends StatefulWidget {
  const ChartWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  State<ChartWidget> createState() => _ChartWidgetState();
}

class _ChartWidgetState extends State<ChartWidget> {
  bool _legend = true;

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    return StoreListener(
      keyName: 'c:${w.id}',
      builder: (c) {
        final bufs = c.store.charts[w.id] ?? const {};
        final series = w.series;
        final cs = Theme.of(c).colorScheme;
        final empty = series.every((s) => (bufs[s.id] ?? const []).isEmpty);
        final showLegend = w.legend && _legend;
        return Frame(
          w: w,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (showLegend)
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var i = 0; i < series.length; i++)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: seriesColor(series[i], i), borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 4),
                      Text(series[i].lbl ?? series[i].id, style: Theme.of(c).textTheme.labelMedium),
                      if (w.vals && (bufs[series[i].id] ?? const []).isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text('${fmtValue(bufs[series[i].id]!.last.$2)}${w.unit ?? ''}', style: Theme.of(c).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ]),
                  TextButton(style: TextButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: () => setState(() => _legend = false), child: const Text('hide')),
                ],
              ),
            if (!showLegend && w.legend)
              Align(alignment: Alignment.centerRight, child: TextButton(style: TextButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: () => setState(() => _legend = true), child: const Text('legend'))),
            SizedBox(
              height: 180,
              child: empty
                  ? Center(child: Text('waiting for data', style: TextStyle(color: cs.onSurfaceVariant)))
                  : Padding(padding: const EdgeInsets.only(right: 8, top: 8), child: w.style == 'bar' ? _bars(c, series, bufs) : _lines(c, series, bufs)),
            ),
          ]),
        );
      },
    );
  }

  Widget _axisText(BuildContext c, String s) => Text(s, style: TextStyle(fontSize: 10, color: Theme.of(c).colorScheme.onSurfaceVariant));

  Widget _lines(BuildContext c, List<ChartSeries> series, Map<String, List<(double, double)>> bufs) {
    final w = widget.w;
    double minX = double.infinity, maxX = -double.infinity;
    for (final s in series) {
      for (final p in bufs[s.id] ?? const <(double, double)>[]) {
        if (p.$1 < minX) minX = p.$1;
        if (p.$1 > maxX) maxX = p.$1;
      }
    }
    if (maxX - minX < 1000) maxX = minX + 1000;
    final grid = Theme.of(c).colorScheme.outlineVariant;
    return LineChart(
      LineChartData(
        minX: minX / 1000,
        maxX: maxX / 1000,
        clipData: const FlClipData.all(),
        gridData: FlGridData(getDrawingHorizontalLine: (_) => FlLine(color: grid, strokeWidth: 1), getDrawingVerticalLine: (_) => FlLine(color: grid, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: ((maxX - minX) / 1000 / 4).clamp(1, double.infinity),
              getTitlesWidget: (v, meta) => v == meta.min || v == meta.max ? const SizedBox.shrink() : _axisText(c, hms(DateTime.fromMillisecondsSinceEpoch((v * 1000).round()))),
            ),
          ),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: (v, meta) => _axisText(c, '${fmtValue(v)}${w.unit ?? ''}'))),
        ),
        lineBarsData: [
          for (var i = 0; i < series.length; i++)
            LineChartBarData(
              spots: [for (final p in bufs[series[i].id] ?? const <(double, double)>[]) FlSpot(p.$1 / 1000, p.$2)],
              color: seriesColor(series[i], i),
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: w.style == 'area', color: seriesColor(series[i], i).withValues(alpha: 0.2)),
            ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  Widget _bars(BuildContext c, List<ChartSeries> series, Map<String, List<(double, double)>> bufs) {
    final w = widget.w;
    final ts = <double>{};
    for (final s in series) {
      for (final p in bufs[s.id] ?? const <(double, double)>[]) {
        ts.add(p.$1);
      }
    }
    final xs = ts.toList()..sort();
    final idx = {for (var i = 0; i < xs.length; i++) xs[i]: i};
    final cols = <int, List<double?>>{for (var i = 0; i < xs.length; i++) i: List.filled(series.length, null)};
    for (var si = 0; si < series.length; si++) {
      for (final p in bufs[series[si].id] ?? const <(double, double)>[]) {
        cols[idx[p.$1]!]![si] = p.$2;
      }
    }
    final grid = Theme.of(c).colorScheme.outlineVariant;
    return BarChart(
      BarChartData(
        gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: grid, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (xs.length / 4).ceilToDouble().clamp(1, double.infinity),
              getTitlesWidget: (v, meta) => v.round() < xs.length ? _axisText(c, hms(DateTime.fromMillisecondsSinceEpoch(xs[v.round()].round()))) : const SizedBox.shrink(),
            ),
          ),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: (v, meta) => _axisText(c, '${fmtValue(v)}${w.unit ?? ''}'))),
        ),
        barGroups: [
          for (var i = 0; i < xs.length; i++)
            BarChartGroupData(x: i, barsSpace: 1, barRods: [
              for (var si = 0; si < series.length; si++) BarChartRodData(toY: cols[i]![si] ?? 0, color: seriesColor(series[si], si), width: 4, borderRadius: BorderRadius.zero),
            ]),
        ],
      ),
      duration: Duration.zero,
    );
  }
}
