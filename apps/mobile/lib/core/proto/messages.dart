// Hand-written mirror of protocol/schema/v1. Unknown keys are kept on widgets and ignored elsewhere.
typedef Json = Map<String, dynamic>;

const kWidgetTypes = {
  'label', 'button', 'switch', 'slider', 'number', 'text', 'textarea', 'select', 'flags', 'color',
  'datetime', 'joystick', 'dpad', 'gauge', 'progress', 'display', 'led', 'chart', 'log', 'table',
  'image', 'stream', 'clock', 'map', 'textblock', 'header', 'group', 'page', 'row', 'spacer',
};

const kCaps = {'wifi', 'ota', 'otaurl', 'chart', 'ble', 'ntp', 'ntfy', 'pin', 'reboot', 'info'};

double? _d(dynamic v) => v is num ? v.toDouble() : null;
int? _i(dynamic v) => v is num ? v.toInt() : null;
bool? _b(dynamic v) => v is bool ? v : null;
String? _s(dynamic v) => v is String ? v : null;

class ChartSeries {
  const ChartSeries({required this.id, this.lbl, this.color});
  final String id;
  final String? lbl;
  final String? color;
  static ChartSeries? from(dynamic j) =>
      j is Map && j['id'] is String ? ChartSeries(id: j['id'] as String, lbl: _s(j['lbl']), color: _s(j['color'])) : null;
}

class GaugeZone {
  const GaugeZone({required this.from, required this.to, required this.color});
  final double from;
  final double to;
  final String color;
  static GaugeZone? parse(dynamic j) => j is Map && j['from'] is num && j['to'] is num && j['color'] is String
      ? GaugeZone(from: (j['from'] as num).toDouble(), to: (j['to'] as num).toDouble(), color: j['color'] as String)
      : null;
}

class TableCol {
  const TableCol({this.lbl, this.w = 1, this.align = 'left'});
  final String? lbl;
  final double w;
  final String align;
  static TableCol? from(dynamic j) =>
      j is Map ? TableCol(lbl: _s(j['lbl']), w: _d(j['w']) ?? 1, align: _s(j['align']) ?? 'left') : null;
}

/// Immutable widget description; `merge` returns a patched copy (used by `prop`).
class WidgetDef {
  WidgetDef(Json props) : props = Map.unmodifiable(props);
  final Json props;

  static WidgetDef? from(dynamic j) =>
      j is Map && j['id'] is String && j['ty'] is String ? WidgetDef(Map<String, dynamic>.from(j)) : null;

  WidgetDef merge(Map<dynamic, dynamic> p) {
    final n = Map<String, dynamic>.from(props);
    for (final e in p.entries) {
      final k = e.key.toString();
      if (k == 'id' || k == 'ty') continue;
      n[k] = e.value;
    }
    return WidgetDef(n);
  }

  dynamic operator [](String k) => props[k];

  String get id => props['id'] as String;
  String get ty => props['ty'] as String;
  String? get lbl => _s(props['lbl']);
  String? get grp => _s(props['grp']);
  String? get page => _s(props['page']);
  String? get row => _s(props['row']);
  bool get sq => _b(props['sq']) ?? false;
  bool get dis => _b(props['dis']) ?? false;
  bool get vis => _b(props['vis']) ?? true;
  bool get ro => _b(props['ro']) ?? false;
  bool get readOnly => ro || dis;
  String? get hint => _s(props['hint']);
  String? get icon => _s(props['icon']);
  String? get color => _s(props['color']);
  String? get unit => _s(props['unit']);
  String? get fmt => _s(props['fmt']);
  bool get hold => _b(props['hold']) ?? false;
  String? get on => _s(props['on']);
  String? get off => _s(props['off']);
  double get min => _d(props['min']) ?? 0;
  double get max => _d(props['max']) ?? 100;
  double get step {
    final s = _d(props['step']);
    return s != null && s > 0 ? s : 1;
  }
  bool get spin => _b(props['spin']) ?? false;
  int? get maxlen => _i(props['maxlen']);
  bool get secret => _b(props['secret']) ?? false;
  String? get re => _s(props['re']);
  int get rows => _i(props['rows']) ?? 5;
  List<String> get opts => props['opts'] is List ? (props['opts'] as List).map((e) => e.toString()).toList() : const [];
  String? get style => _s(props['style']);
  String get mode => _s(props['mode']) ?? 'datetime';
  bool? get center => _b(props['center']);
  bool get exp => _b(props['exp']) ?? false;
  List<GaugeZone> get zones =>
      props['zones'] is List ? (props['zones'] as List).map(GaugeZone.parse).whereType<GaugeZone>().toList() : const [];
  int get digits => _i(props['digits']) ?? 4;
  bool get rgb => _b(props['rgb']) ?? false;
  List<ChartSeries> get series =>
      props['series'] is List ? (props['series'] as List).map(ChartSeries.from).whereType<ChartSeries>().toList() : const [];
  int get win => _i(props['win']) ?? 300;
  bool get legend => _b(props['legend']) ?? true;
  bool get vals => _b(props['vals']) ?? false;
  int get cap => _i(props['cap']) ?? 200;
  List<TableCol> get cols =>
      props['cols'] is List ? (props['cols'] as List).map(TableCol.from).whereType<TableCol>().toList() : const [];
  String? get src => _s(props['src']);
  int get zoom => _i(props['zoom']) ?? 12;
  String? get text => _s(props['text']);
  bool get fold => _b(props['fold']) ?? false;

  /// Relative width inside a row (default 1).
  double get sizeW {
    final s = props['size'];
    if (s is num) return s.toDouble();
    if (s is List && s.isNotEmpty && s[0] is num) return (s[0] as num).toDouble();
    return 1;
  }

  /// Fixed height in px when `size` is `[w, h]` with h > 0.
  double? get sizeH {
    final s = props['size'];
    if (s is List && s.length > 1 && s[1] is num && (s[1] as num) > 0) return (s[1] as num).toDouble();
    return null;
  }
}

sealed class D2C {
  const D2C(this.raw);
  final Json raw;

  static D2C? from(Json m) {
    final t = m['t'];
    if (t is! String) return null;
    switch (t) {
      case 'hello':
        return HelloMsg.from(m);
      case 'auth':
        return AuthMsg.from(m);
      case 'ui':
        return UiMsg.from(m);
      case 'upd':
        return UpdMsg.from(m);
      case 'pts':
        return PtsMsg.from(m);
      case 'toast':
        return ToastMsg.from(m);
      case 'log':
        return LogMsg.from(m);
      case 'prop':
        return PropMsg.from(m);
      case 'dlg':
        return DlgMsg.from(m);
      case 'sys':
        return SysMsg.from(m);
      case 'err':
        return ErrMsg.from(m);
      default:
        return UnknownMsg(m);
    }
  }
}

class UnknownMsg extends D2C {
  const UnknownMsg(super.raw);
  String get t => raw['t'] as String;
}

class HelloMsg extends D2C {
  HelloMsg(super.raw);
  static D2C from(Json m) => m['id'] is String && m['name'] is String ? HelloMsg(m) : UnknownMsg(m);
  int get v => _i(raw['v']) ?? 0;
  String get name => raw['name'] as String;
  String get id => raw['id'] as String;
  String? get proj => _s(raw['proj']);
  String? get icon => _s(raw['icon']);
  String? get fw => _s(raw['fw']);
  String get auth => _s(raw['auth']) ?? 'none';
  bool get ok => _b(raw['ok']) ?? false;
  String? get nonce => _s(raw['nonce']);
  int? get lock => _i(raw['lock']);
  int get up => _i(raw['up']) ?? 0;
  List<String> get caps => raw['caps'] is List ? (raw['caps'] as List).whereType<String>().toList() : const [];
  bool hasCap(String c) => caps.contains(c);
}

class AuthMsg extends D2C {
  const AuthMsg(super.raw);
  static D2C from(Json m) => m['ok'] is bool ? AuthMsg(m) : UnknownMsg(m);
  bool get ok => raw['ok'] as bool;
  String? get tok => _s(raw['tok']);
  int? get left => _i(raw['left']);
  int? get lock => _i(raw['lock']);
}

class UiMsg extends D2C {
  UiMsg(super.raw) : widgets = (raw['w'] as List).map(WidgetDef.from).whereType<WidgetDef>().toList();
  static D2C from(Json m) => m['w'] is List ? UiMsg(m) : UnknownMsg(m);
  final List<WidgetDef> widgets;
  int? get rev => _i(raw['rev']);
}

class UpdMsg extends D2C {
  const UpdMsg(super.raw);
  static D2C from(Json m) => m['v'] is Map ? UpdMsg(m) : UnknownMsg(m);
  Map<String, dynamic> get values => Map<String, dynamic>.from(raw['v'] as Map);
}

class PtsMsg extends D2C {
  const PtsMsg(super.raw);
  static D2C from(Json m) => m['id'] is String && m['s'] is String && m['p'] is List ? PtsMsg(m) : UnknownMsg(m);
  String get id => raw['id'] as String;
  String get s => raw['s'] as String;
  List<(double, double)> get points => [
        for (final p in raw['p'] as List)
          if (p is List && p.length >= 2 && p[0] is num && p[1] is num) ((p[0] as num).toDouble(), (p[1] as num).toDouble()),
      ];
}

class ToastMsg extends D2C {
  const ToastMsg(super.raw);
  static D2C from(Json m) => m['msg'] is String ? ToastMsg(m) : UnknownMsg(m);
  String get lvl => _s(raw['lvl']) ?? 'info';
  String get msg => raw['msg'] as String;
}

class LogMsg extends D2C {
  const LogMsg(super.raw);
  static D2C from(Json m) => m['msg'] is String ? LogMsg(m) : UnknownMsg(m);
  String get msg => raw['msg'] as String;
  String? get id => _s(raw['id']);
  String? get c => _s(raw['c']);
  double? get ts => _d(raw['ts']);
}

class PropMsg extends D2C {
  const PropMsg(super.raw);
  static D2C from(Json m) => m['id'] is String && m['p'] is Map ? PropMsg(m) : UnknownMsg(m);
  String get id => raw['id'] as String;
  Map<dynamic, dynamic> get p => raw['p'] as Map;
}

class DlgMsg extends D2C {
  const DlgMsg(super.raw);
  static D2C from(Json m) => m['id'] is String ? DlgMsg(m) : UnknownMsg(m);
  String get id => raw['id'] as String;
  String? get kind => _s(raw['kind']);
  String? get title => _s(raw['title']);
  String get msg => _s(raw['msg']) ?? '';
  String? get def => _s(raw['def']);
  int get timeout => _i(raw['timeout']) ?? 60;
  bool get close => _b(raw['close']) ?? false;
}

class SysMsg extends D2C {
  const SysMsg(super.raw);
  static D2C from(Json m) => m['cmd'] is String ? SysMsg(m) : UnknownMsg(m);
  String get cmd => raw['cmd'] as String;
  bool? get ok => _b(raw['ok']);
  String? get msg => _s(raw['msg']);
}

class ErrMsg extends D2C {
  const ErrMsg(super.raw);
  static D2C from(Json m) => m['code'] is num ? ErrMsg(m) : UnknownMsg(m);
  int get code => (raw['code'] as num).toInt();
  String? get msg => _s(raw['msg']);
  String? get ref => _s(raw['ref']);
}

/// Typed view of a `sys info` reply.
class SysInfo {
  const SysInfo(this.raw);
  final Json raw;
  String? get chip => _s(raw['chip']);
  String? get fw => _s(raw['fw']);
  String? get repo => _s(raw['repo']);
  String? get about => _s(raw['about']);
  String? get rr => _s(raw['rr']);
  int? get heap => _i(raw['heap']);
  int? get heapmin => _i(raw['heapmin']);
  int? get up => _i(raw['up']);
  String? get ip => _s(raw['ip']);
  String? get ssid => _s(raw['ssid']);
  int? get rssi => _i(raw['rssi']);
  String? get mac => _s(raw['mac']);
  int? get time => _i(raw['time']);
  int? get clients => _i(raw['clients']);
}

class WifiStatus {
  const WifiStatus(this.raw);
  final Json raw;
  String? get st => _s(raw['st']);
  String? get ip => _s(raw['ip']);
  String? get ssid => _s(raw['ssid']);
  int? get rssi => _i(raw['rssi']);
}

class WifiAp {
  const WifiAp({required this.ssid, required this.rssi, required this.enc});
  final String ssid;
  final int rssi;
  final bool enc;
  static WifiAp? from(dynamic j) => j is Map && j['ssid'] is String
      ? WifiAp(ssid: j['ssid'] as String, rssi: _i(j['rssi']) ?? -100, enc: _b(j['enc']) ?? false)
      : null;
}
