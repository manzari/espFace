import '../../core/proto/messages.dart';

/// A device in the list. `key` is stable for routing; `id` is the protocol device id once known.
class SavedDevice {
  const SavedDevice({required this.key, required this.host, this.id, required this.name, this.proj, this.icon, this.fw, this.order = 0});

  final String key;
  final String host;
  final String? id;
  final String name;
  final String? proj;
  final String? icon;
  final String? fw;
  final int order;

  String get group => proj ?? '';

  SavedDevice copyWith({String? host, String? id, String? name, String? proj, String? icon, String? fw, int? order}) => SavedDevice(
        key: key,
        host: host ?? this.host,
        id: id ?? this.id,
        name: name ?? this.name,
        proj: proj ?? this.proj,
        icon: icon ?? this.icon,
        fw: fw ?? this.fw,
        order: order ?? this.order,
      );

  SavedDevice learn(HelloMsg h) => copyWith(id: h.id, name: h.name, proj: h.proj, icon: h.icon, fw: h.fw);

  Map<String, dynamic> toJson() => {'key': key, 'host': host, 'id': ?id, 'name': name, 'proj': ?proj, 'icon': ?icon, 'fw': ?fw, 'order': order};

  static SavedDevice? fromJson(dynamic j) {
    if (j is! Map || j['key'] is! String || j['host'] is! String) return null;
    return SavedDevice(
      key: j['key'] as String,
      host: j['host'] as String,
      id: j['id'] is String ? j['id'] as String : null,
      name: j['name'] is String ? j['name'] as String : j['host'] as String,
      proj: j['proj'] is String ? j['proj'] as String : null,
      icon: j['icon'] is String ? j['icon'] as String : null,
      fw: j['fw'] is String ? j['fw'] as String : null,
      order: j['order'] is num ? (j['order'] as num).toInt() : 0,
    );
  }

  static String keyFor({String? id, required String host}) => id != null && id.isNotEmpty ? id : 'host:$host';
}

/// A device seen by mDNS (`_espface._tcp`, TXT id/name/v/proj/icon).
class DiscoveredDevice {
  const DiscoveredDevice({required this.id, required this.name, required this.host, this.proj, this.icon, this.v});
  final String id;
  final String name;
  final String host;
  final String? proj;
  final String? icon;
  final int? v;
}

/// `espface://<host>?id=..&name=..&proj=..`
DiscoveredDevice? parseQr(String text) {
  final u = Uri.tryParse(text.trim());
  if (u == null || u.scheme != 'espface' || u.host.isEmpty) return null;
  final host = u.hasPort ? '${u.host}:${u.port}' : u.host;
  final id = u.queryParameters['id'] ?? '';
  return DiscoveredDevice(id: id, name: u.queryParameters['name'] ?? host, host: host, proj: u.queryParameters['proj'], icon: u.queryParameters['icon']);
}
