import 'dart:math' as math;

/// Value helpers shared by the renderer (mirrors web/src/widgets/common.tsx).
double asNum(dynamic v, [double def = 0]) {
  if (v is num && v.isFinite) return v.toDouble();
  if (v is String && v.isNotEmpty) {
    final p = double.tryParse(v);
    if (p != null && p.isFinite) return p;
  }
  return def;
}

String asStr(dynamic v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is num) return fmtValue(v);
  return v.toString();
}

double clampNum(double v, double lo, double hi) => math.min(hi, math.max(lo, v));

String hexColor(num n) {
  final i = n.round().clamp(0, 0xffffff);
  return '#${i.toRadixString(16).padLeft(6, '0')}';
}

int decimals(double step) {
  final s = step.toString();
  if (s.contains('e')) return 6;
  final i = s.indexOf('.');
  if (i < 0) return 0;
  final frac = s.substring(i + 1).replaceAll(RegExp(r'0+$'), '');
  return frac.length;
}

String _trim(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.round().toString();
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return s;
}

/// printf-style subset: %d %f %.2f %5.1f %s %%
String fmtValue(dynamic v, [String? f]) {
  if (f == null || f.isEmpty) return v is num ? _trim(v.toDouble()) : asStr(v);
  return f.replaceAllMapped(RegExp(r'%(\d*)(?:\.(\d+))?([dfs%])'), (m) {
    final w = m[1] ?? '';
    final p = m[2];
    final c = m[3];
    String s;
    if (c == '%') return '%';
    if (c == 's') {
      s = asStr(v);
    } else if (c == 'd') {
      s = asNum(v).round().toString();
    } else {
      s = asNum(v).toStringAsFixed(p != null ? int.parse(p) : 2);
    }
    return w.isNotEmpty ? s.padLeft(int.parse(w)) : s;
  });
}

String pad2(int n) => n.toString().padLeft(2, '0');

/// fmt tokens: YYYY MM DD HH mm ss; default "HH:mm:ss".
String formatClock(DateTime d, [String? f]) {
  final fm = (f == null || f.isEmpty) ? 'HH:mm:ss' : f;
  return fm.replaceAllMapped(RegExp('YYYY|MM|DD|HH|mm|ss'), (m) {
    switch (m[0]) {
      case 'YYYY':
        return d.year.toString();
      case 'MM':
        return pad2(d.month);
      case 'DD':
        return pad2(d.day);
      case 'HH':
        return pad2(d.hour);
      case 'mm':
        return pad2(d.minute);
      default:
        return pad2(d.second);
    }
  });
}

String hms(DateTime d) => '${pad2(d.hour)}:${pad2(d.minute)}:${pad2(d.second)}';

String fmtUptime(int? ms) {
  if (ms == null) return '-';
  final s = ms ~/ 1000;
  final d = s ~/ 86400, h = (s % 86400) ~/ 3600, m = (s % 3600) ~/ 60;
  return '${d > 0 ? '${d}d ' : ''}${h}h ${m}m ${s % 60}s';
}

String fmtKb(int? n) => n == null ? '-' : '${(n / 1024).toStringAsFixed(1)} KB';
