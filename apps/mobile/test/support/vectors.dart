import 'dart:convert';
import 'dart:io';

/// Loads protocol/vectors/*.json relative to the package root (flutter test runs with cwd = apps/mobile).
class Vector {
  Vector(this.file, Map<String, dynamic> j)
      : name = j['name'] as String,
        dir = j['dir'] as String,
        valid = j['valid'] != false,
        msg = Map<String, dynamic>.from(j['msg'] as Map),
        hmac = j['hmac'] is Map ? Map<String, dynamic>.from(j['hmac'] as Map) : null;
  final String file;
  final String name;
  final String dir;
  final bool valid;
  final Map<String, dynamic> msg;
  final Map<String, dynamic>? hmac;
}

Directory protocolDir() {
  for (final p in ['../../protocol', '../protocol', 'protocol']) {
    final d = Directory(p);
    if (d.existsSync()) return d;
  }
  throw StateError('protocol directory not found from ${Directory.current.path}');
}

List<Vector> loadVectors() {
  final dir = Directory('${protocolDir().path}/vectors');
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      for (final j in jsonDecode(f.readAsStringSync()) as List) Vector(f.uri.pathSegments.last, Map<String, dynamic>.from(j as Map)),
  ];
}

Map<String, dynamic> vectorMsg(String name) => loadVectors().firstWhere((v) => v.name == name).msg;
