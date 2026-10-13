import 'package:flutter/material.dart';

import '../../../core/proto/messages.dart';
import '../../../core/proto/values.dart';
import '../common.dart';
import '../ui_store.dart';

/// Monospace line list, newest at the bottom; the reversed list keeps it pinned there while allowing scroll-back.
class LogLines extends StatelessWidget {
  const LogLines({super.key, required this.lines, required this.height});
  final List<LogLine> lines;
  final double height;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
      child: ListView.builder(
        reverse: true,
        itemCount: lines.length,
        itemBuilder: (c, i) {
          final l = lines[lines.length - 1 - i];
          return Text.rich(
            TextSpan(children: [
              TextSpan(text: '${hms(l.ts)} ', style: TextStyle(color: cs.onSurfaceVariant)),
              TextSpan(text: l.msg, style: TextStyle(color: parseColor(l.c))),
            ]),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4),
          );
        },
      ),
    );
  }
}

class LogWidget extends StatelessWidget {
  const LogWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  Widget build(BuildContext context) => Frame(
        w: w,
        child: StoreListener(keyName: 'l:${w.id}', builder: (c) => LogLines(lines: c.store.logs[w.id] ?? const [], height: w.rows * 17.0 + 8)),
      );
}

class TableWidget extends StatelessWidget {
  const TableWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  Widget build(BuildContext context) => ValueOf(
        id: w.id,
        builder: (c, v) {
          final cols = w.cols;
          final rows = v is List ? v.whereType<List>().toList() : const <List>[];
          final n = cols.isNotEmpty ? cols.length : rows.fold<int>(0, (a, r) => r.length > a ? r.length : a);
          if (n == 0) return Frame(w: w, child: Text('no data', style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant)));
          TextAlign align(int j) => switch (j < cols.length ? cols[j].align : 'left') { 'right' => TextAlign.right, 'center' => TextAlign.center, _ => TextAlign.left };
          final cs = Theme.of(c).colorScheme;
          return Frame(
            w: w,
            child: Table(
              columnWidths: {for (var j = 0; j < n; j++) j: FlexColumnWidth(j < cols.length ? cols[j].w : 1)},
              border: TableBorder(horizontalInside: BorderSide(color: cs.outlineVariant)),
              children: [
                if (cols.isNotEmpty)
                  TableRow(children: [
                    for (var j = 0; j < n; j++) Padding(padding: const EdgeInsets.all(6), child: Text(j < cols.length ? cols[j].lbl ?? '' : '', textAlign: align(j), style: Theme.of(c).textTheme.labelLarge)),
                  ]),
                for (final r in rows)
                  TableRow(children: [
                    for (var j = 0; j < n; j++) Padding(padding: const EdgeInsets.all(6), child: Text(j < r.length ? asStr(r[j]) : '', textAlign: align(j))),
                  ]),
              ],
            ),
          );
        },
      );
}

/// The device pushes unix seconds once in a while; the client ticks locally from the moment it arrived.
class ClockWidget extends StatelessWidget {
  const ClockWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  Widget build(BuildContext context) => Frame(
        w: w,
        child: ValueOf(
          id: w.id,
          builder: (c, v) => Ticker(
            builder: (c) {
              final unix = asNum(v).round();
              final at = c.store.valueAt[w.id] ?? DateTime.now();
              final text = unix > 0 ? formatClock(DateTime.fromMillisecondsSinceEpoch(unix * 1000).add(DateTime.now().difference(at)), w.fmt) : '--:--:--';
              return Text(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 28, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]));
            },
          ),
        ),
      );
}
