import 'package:flutter/foundation.dart';

import '../../core/proto/messages.dart';

class LogLine {
  const LogLine({required this.ts, required this.msg, this.c});
  final DateTime ts;
  final String msg;
  final String? c;
}

class DeviceDialog {
  const DeviceDialog({required this.id, required this.kind, this.title, required this.msg, this.def, required this.timeout, required this.at});
  final String id;
  final String kind;
  final String? title;
  final String msg;
  final String? def;
  final int timeout;
  final DateTime at;
}

class Toast {
  const Toast({required this.id, required this.lvl, required this.msg, required this.at});
  final int id;
  final String lvl;
  final String msg;
  final DateTime at;
}

class OtaState {
  const OtaState({required this.pct, this.done = false, this.ok, this.msg});
  final int pct;
  final bool done;
  final bool? ok;
  final String? msg;
}

sealed class LayoutItem {
  const LayoutItem();
}

class WidgetItem extends LayoutItem {
  const WidgetItem(this.id);
  final String id;
}

class RowLayout extends LayoutItem {
  RowLayout(this.id);
  final String id;
  final List<String> items = [];
}

class Block {
  Block({required this.kind, required this.id});
  final String kind; // group | free
  final String id;
  final List<LayoutItem> items = [];
}

class PageLayout {
  PageLayout({required this.id, required this.lbl, this.icon});
  final String id;
  final String lbl;
  final String? icon;
  final List<Block> blocks = [];
}

class _Key extends ChangeNotifier {
  int version = 0;
  void bump() {
    version++;
    notifyListeners();
  }
}

const _uptimeLimit = 1099511627776.0; // 2^40
const _consoleCap = 500;
const _structural = {'vis', 'page', 'grp', 'row'};

/// Everything the renderer shows. Widgets listen to fine-grained keys (`v:id`, `w:id`, `c:id`,
/// `l:id`, `layout`, `page`, `device`, `dlg`, `toast`, `sys`, `sys:cmd`, `console`) so only touched parts rebuild.
class UiStore {
  UiStore({DateTime Function()? now}) : now = now ?? DateTime.now;

  final DateTime Function() now;
  int rev = -1;
  final Map<String, WidgetDef> widgets = {};
  List<String> order = [];
  final Map<String, dynamic> values = {};
  final Map<String, DateTime> valueAt = {};
  final Map<String, Map<String, List<(double, double)>>> charts = {};
  final Map<String, List<LogLine>> logs = {};
  final List<LogLine> console = [];
  List<DeviceDialog> dialogs = [];
  List<Toast> toasts = [];
  String page = '';
  HelloMsg? device;
  DateTime? helloAt;
  SysInfo? sysInfo;
  WifiStatus? wifi;
  List<WifiAp>? wifiScan;
  OtaState? ota;
  SysMsg? lastSys;
  List<PageLayout>? _layoutCache;
  final Map<String, _Key> _keys = {};
  int _toastSeq = 0;

  Listenable listen(String key) => _keys.putIfAbsent(key, _Key.new);
  int version(String key) => _keys[key]?.version ?? 0;
  void emit(String key) => _keys[key]?.bump();

  void apply(D2C m) {
    switch (m) {
      case HelloMsg():
        _onHello(m);
      case UiMsg():
        _onUi(m);
      case UpdMsg():
        _onUpd(m);
      case PtsMsg():
        _onPts(m);
      case ToastMsg():
        addToast(m.lvl, m.msg);
      case LogMsg():
        _onLog(m);
      case PropMsg():
        _onProp(m);
      case DlgMsg():
        _onDlg(m);
      case SysMsg():
        _onSys(m);
      case ErrMsg():
        addToast('err', '${m.msg ?? 'error'}${m.ref != null ? ' (${m.ref})' : ''} [${m.code}]');
      case AuthMsg():
      case UnknownMsg():
        break;
    }
  }

  // ---- session ---------------------------------------------------------
  void _onHello(HelloMsg m) {
    device = m;
    helloAt = now();
    emit('device');
  }

  bool hasCap(String cap) => device?.hasCap(cap) ?? false;

  /// Uptime timestamps (< 2^40) are rebased on the hello: wall = helloAt + (ts - up).
  DateTime wallTime(double ts) {
    if (!ts.isFinite) return now();
    if (ts >= _uptimeLimit) return DateTime.fromMillisecondsSinceEpoch(ts.round());
    final d = device;
    final at = helloAt;
    if (d == null || at == null) return now();
    return at.add(Duration(milliseconds: (ts - d.up).round()));
  }

  // ---- ui model --------------------------------------------------------
  void _onUi(UiMsg m) {
    rev = m.rev ?? rev;
    widgets.clear();
    order = [];
    for (final w in m.widgets) {
      if (widgets.containsKey(w.id)) continue;
      widgets[w.id] = w;
      order.add(w.id);
    }
    _layoutCache = null;
    final p = pages();
    if (!p.any((x) => x.id == page)) page = p.isNotEmpty ? p.first.id : '';
    emit('layout');
    for (final id in order) {
      emit('w:$id');
    }
  }

  void _onProp(PropMsg m) {
    final w = widgets[m.id];
    if (w == null) return;
    widgets[m.id] = w.merge(m.p);
    emit('w:${m.id}');
    if (m.p.keys.any((k) => _structural.contains(k))) {
      _layoutCache = null;
      emit('layout');
    }
  }

  String firstPage() {
    for (final id in order) {
      if (widgets[id]!.ty == 'page') return id;
    }
    return '';
  }

  String pageOf(WidgetDef w) {
    if (w.page != null) return w.page!;
    final row = w.row != null ? widgets[w.row] : null;
    if (row?.page != null) return row!.page!;
    final grp = (w.grp != null ? widgets[w.grp] : null) ?? (row?.grp != null ? widgets[row!.grp] : null);
    if (grp?.page != null) return grp!.page!;
    return firstPage();
  }

  List<PageLayout> pages() => layout();

  List<PageLayout> layout() {
    final cached = _layoutCache;
    if (cached != null) return cached;
    final result = <PageLayout>[];
    final byId = <String, PageLayout>{};
    PageLayout pageFor(String id) => byId.putIfAbsent(id, () {
          final w = widgets[id];
          final p = PageLayout(id: id, lbl: w?.lbl ?? id, icon: w?.icon);
          result.add(p);
          return p;
        });
    for (final id in order) {
      if (widgets[id]!.ty == 'page') pageFor(id);
    }
    if (result.isEmpty) pageFor('');
    final cards = <String, Block>{};
    final rows = <String, RowLayout>{};
    Block free(PageLayout p) {
      final last = p.blocks.isNotEmpty ? p.blocks.last : null;
      if (last != null && last.kind == 'free') return last;
      final b = Block(kind: 'free', id: 'free${p.blocks.length}');
      p.blocks.add(b);
      return b;
    }

    for (final id in order) {
      final w = widgets[id]!;
      if (w.ty == 'page') continue;
      final p = byId[pageOf(w)] ?? result.first;
      if (w.ty == 'group') {
        final b = Block(kind: 'group', id: id);
        cards[id] = b;
        p.blocks.add(b);
        continue;
      }
      final card = w.grp != null ? cards[w.grp] : null;
      if (w.ty == 'row') {
        final r = RowLayout(id);
        rows[id] = r;
        (card ?? free(p)).items.add(r);
        continue;
      }
      final row = w.row != null ? rows[w.row] : null;
      if (row != null) {
        row.items.add(id);
      } else {
        (card ?? free(p)).items.add(WidgetItem(id));
      }
    }
    return _layoutCache = result;
  }

  void setPage(String id) {
    if (page == id) return;
    page = id;
    emit('page');
  }

  // ---- values ----------------------------------------------------------
  void _onUpd(UpdMsg m) {
    final at = now();
    for (final e in m.values.entries) {
      values[e.key] = e.value;
      valueAt[e.key] = at;
      emit('v:${e.key}');
    }
  }

  void setLocal(String id, dynamic v) {
    values[id] = v;
    valueAt[id] = now();
    emit('v:$id');
  }

  void _onPts(PtsMsg m) {
    final chart = charts.putIfAbsent(m.id, () => {});
    final pts = chart.putIfAbsent(m.s, () => []);
    for (final p in m.points) {
      final ts = wallTime(p.$1).millisecondsSinceEpoch.toDouble();
      if (pts.isNotEmpty && ts <= pts.last.$1) continue;
      pts.add((ts, p.$2));
    }
    final win = (widgets[m.id]?.win ?? 300) * 1000;
    var latest = 0.0;
    for (final s in chart.values) {
      if (s.isNotEmpty && s.last.$1 > latest) latest = s.last.$1;
    }
    for (final s in chart.values) {
      var cut = 0;
      while (cut < s.length && s[cut].$1 < latest - win) {
        cut++;
      }
      if (cut > 0) s.removeRange(0, cut);
    }
    emit('c:${m.id}');
  }

  void _onLog(LogMsg m) {
    final line = LogLine(ts: m.ts != null ? wallTime(m.ts!) : now(), msg: m.msg, c: m.c);
    final id = m.id;
    if (id == null) {
      console.add(line);
      if (console.length > _consoleCap) console.removeRange(0, console.length - _consoleCap);
      emit('console');
      return;
    }
    final lines = logs.putIfAbsent(id, () => []);
    if (m.ts != null && lines.any((l) => l.ts == line.ts && l.msg == line.msg)) return;
    lines.add(line);
    final cap = widgets[id]?.cap ?? 200;
    if (lines.length > cap) lines.removeRange(0, lines.length - cap);
    emit('l:$id');
  }

  // ---- dialogs and toasts ---------------------------------------------
  void _onDlg(DlgMsg m) {
    if (m.close) return closeDialog(m.id);
    if (m.kind != 'confirm' && m.kind != 'prompt') return;
    if (dialogs.any((d) => d.id == m.id)) return;
    dialogs = [...dialogs, DeviceDialog(id: m.id, kind: m.kind!, title: m.title, msg: m.msg, def: m.def, timeout: m.timeout, at: now())];
    emit('dlg');
  }

  void closeDialog(String id) {
    final n = dialogs.length;
    dialogs = dialogs.where((d) => d.id != id).toList();
    if (dialogs.length != n) emit('dlg');
  }

  void addToast(String lvl, String msg) {
    final l = (lvl == 'warn' || lvl == 'err') ? lvl : 'info';
    toasts = [...toasts, Toast(id: ++_toastSeq, lvl: l, msg: msg, at: now())];
    if (toasts.length > 5) toasts = toasts.sublist(toasts.length - 5);
    emit('toast');
  }

  void removeToast(int id) {
    toasts = toasts.where((t) => t.id != id).toList();
    emit('toast');
  }

  // ---- sys -------------------------------------------------------------
  void _onSys(SysMsg m) {
    lastSys = m;
    switch (m.cmd) {
      case 'info':
        sysInfo = SysInfo(m.raw);
      case 'wifi.status':
        wifi = WifiStatus(m.raw);
      case 'wifi.scan':
        wifiScan = m.raw['ap'] is List ? (m.raw['ap'] as List).map(WifiAp.from).whereType<WifiAp>().toList() : [];
      case 'ota.progress':
        ota = OtaState(pct: (m.raw['pct'] is num ? (m.raw['pct'] as num).toInt() : 0).clamp(0, 100));
      case 'ota.done':
        ota = OtaState(pct: 100, done: true, ok: m.ok ?? false, msg: m.msg);
      case 'ota.begin':
      case 'ota.url':
        if (m.ok == false) ota = OtaState(pct: 0, done: true, ok: false, msg: m.msg);
      default:
        break;
    }
    if (const {'reboot', 'pin.set', 'revoke', 'ota.done'}.contains(m.cmd) && m.ok != null) {
      addToast(m.ok! ? 'info' : 'err', '${m.cmd}: ${m.ok! ? 'ok' : m.msg ?? 'failed'}');
    }
    emit('sys');
    emit('sys:${m.cmd}');
  }

  /// Called on disconnect: transient per-connection state goes away, the UI model stays for a fast reconnect.
  void reset() {
    sysInfo = null;
    wifi = null;
    wifiScan = null;
    ota = null;
    lastSys = null;
    emit('sys');
  }
}
