import 'dart:convert';

import 'messages.dart';

/// Parses one device frame; null for anything that is not a JSON object with a string `t`.
D2C? decode(String text) {
  dynamic m;
  try {
    m = jsonDecode(text);
  } catch (_) {
    return null;
  }
  if (m is! Map || m['t'] is! String) return null;
  return D2C.from(Map<String, dynamic>.from(m));
}

String encode(Map<String, dynamic> msg) => jsonEncode(msg);

/// Client-to-device message builders (PROTOCOL.md 4).
abstract final class C2d {
  static Json hello({String? tok, String client = 'app'}) => {'t': 'hello', 'v': 1, 'client': client, 'tok': ?tok};
  static Json auth(String mac) => {'t': 'auth', 'mac': mac};
  static Json time({DateTime? now}) {
    final d = now ?? DateTime.now();
    return {'t': 'time', 'unix': d.millisecondsSinceEpoch ~/ 1000, 'tz': d.timeZoneOffset.inMinutes};
  }

  static Json set(String id, dynamic v) => {'t': 'set', 'id': id, 'v': v};
  static Json ev(String id, [dynamic v]) => {'t': 'ev', 'id': id, 'v': ?v};
  static Json dlg(String id, bool ok, [String? v]) => {'t': 'dlg', 'id': id, 'ok': ok, if (ok && v != null) 'v': v};
  static Json page(String id) => {'t': 'page', 'id': id};
  static Json sys(String cmd, [Map<String, dynamic> extra = const {}]) => {'t': 'sys', 'cmd': cmd, ...extra};
}
