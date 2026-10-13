import '../../core/proto/messages.dart';
import '../../core/transport/transport.dart';

const _keep = Object();

/// A device in the list. `key` is stable for routing; `id` is the protocol device id once known.
/// One record can carry several addresses (WiFi host, BLE id, USB port, Bluetooth Classic MAC); the
/// connection tries them in [TransportKind] order unless [preferred] pins one.
class SavedDevice {
  const SavedDevice({
    required this.key,
    this.host = '',
    this.id,
    required this.name,
    this.proj,
    this.icon,
    this.fw,
    this.order = 0,
    this.bleId,
    this.usbPort,
    this.usbBaud = 115200,
    this.btAddress,
    this.preferred,
  });

  final String key;
  final String host;
  final String? id;
  final String name;
  final String? proj;
  final String? icon;
  final String? fw;
  final int order;
  final String? bleId;

  /// `vid:pid` in hex, see UsbSerialTransport.portId.
  final String? usbPort;
  final int usbBaud;
  final String? btAddress;
  final TransportKind? preferred;

  String get group => proj ?? '';

  /// Transports this record has an address for, in fallback order.
  List<TransportKind> get configured => [
        if (host.isNotEmpty) TransportKind.wifi,
        if (bleId != null) TransportKind.ble,
        if (usbPort != null) TransportKind.usb,
        if (btAddress != null) TransportKind.bt,
      ];

  /// What to try, honouring the pin and the platform (USB and SPP are Android only).
  List<TransportKind> candidates({required bool serialSupported}) {
    final all = configured.where((k) => serialSupported || (k != TransportKind.usb && k != TransportKind.bt)).toList();
    final p = preferred;
    return p != null && all.contains(p) ? [p] : all;
  }

  /// One line for lists: `192.168.1.5 · BLE · USB 115200`.
  String get addressSummary => [
        if (host.isNotEmpty) host,
        if (bleId != null) 'BLE',
        if (usbPort != null) 'USB $usbBaud',
        if (btAddress != null) 'BT',
      ].join(' · ');

  SavedDevice copyWith({
    String? host,
    String? id,
    String? name,
    String? proj,
    String? icon,
    String? fw,
    int? order,
    String? bleId,
    String? usbPort,
    int? usbBaud,
    String? btAddress,
    Object? preferred = _keep,
  }) =>
      SavedDevice(
        key: key,
        host: host ?? this.host,
        id: id ?? this.id,
        name: name ?? this.name,
        proj: proj ?? this.proj,
        icon: icon ?? this.icon,
        fw: fw ?? this.fw,
        order: order ?? this.order,
        bleId: bleId ?? this.bleId,
        usbPort: usbPort ?? this.usbPort,
        usbBaud: usbBaud ?? this.usbBaud,
        btAddress: btAddress ?? this.btAddress,
        preferred: identical(preferred, _keep) ? this.preferred : preferred as TransportKind?,
      );

  SavedDevice learn(HelloMsg h) => copyWith(id: h.id, name: h.name, proj: h.proj, icon: h.icon, fw: h.fw);

  /// Adds the addresses of [other] (same device reached over another medium); a placeholder name is replaced.
  SavedDevice merge(SavedDevice other) => copyWith(
        host: other.host.isNotEmpty ? other.host : null,
        id: other.id,
        name: name.isEmpty || name == host || name == bleId || name == usbPort || name == btAddress ? other.name : null,
        proj: other.proj,
        icon: other.icon,
        bleId: other.bleId,
        usbPort: other.usbPort,
        usbBaud: other.usbPort != null ? other.usbBaud : null,
        btAddress: other.btAddress,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'host': host,
        'id': ?id,
        'name': name,
        'proj': ?proj,
        'icon': ?icon,
        'fw': ?fw,
        'order': order,
        'ble': ?bleId,
        'usb': ?usbPort,
        if (usbPort != null) 'baud': usbBaud,
        'bt': ?btAddress,
        'pref': ?preferred?.name,
      };

  static SavedDevice? fromJson(dynamic j) {
    if (j is! Map || j['key'] is! String) return null;
    String? str(String k) => j[k] is String && (j[k] as String).isNotEmpty ? j[k] as String : null;
    final host = str('host') ?? '';
    if (host.isEmpty && str('ble') == null && str('usb') == null && str('bt') == null) return null;
    return SavedDevice(
      key: j['key'] as String,
      host: host,
      id: str('id'),
      name: str('name') ?? (host.isNotEmpty ? host : j['key'] as String),
      proj: str('proj'),
      icon: str('icon'),
      fw: str('fw'),
      order: j['order'] is num ? (j['order'] as num).toInt() : 0,
      bleId: str('ble'),
      usbPort: str('usb'),
      usbBaud: j['baud'] is num ? (j['baud'] as num).toInt() : 115200,
      btAddress: str('bt'),
      preferred: TransportKind.parse(str('pref')),
    );
  }

  /// The protocol id when known, else a medium-prefixed address so the same device merges once its id arrives.
  static String keyFor({String? id, String host = '', String? bleId, String? usbPort, String? btAddress}) {
    if (id != null && id.isNotEmpty) return id;
    if (host.isNotEmpty) return 'host:$host';
    if (bleId != null) return 'ble:$bleId';
    if (usbPort != null) return 'usb:$usbPort';
    if (btAddress != null) return 'bt:$btAddress';
    throw ArgumentError('device without any address');
  }
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

/// A peripheral advertising the espFace service; `id`/`protocolId` come from INFO once read.
class BleFound {
  const BleFound({required this.bleId, required this.name, this.rssi, this.protocolId});
  final String bleId;
  final String name;
  final int? rssi;
  final String? protocolId;
}

/// An attached USB serial adapter (Android).
class UsbPortInfo {
  const UsbPortInfo({required this.port, required this.name});
  final String port;
  final String name;
}

/// A paired Bluetooth Classic device (Android).
class BtPairedInfo {
  const BtPairedInfo({required this.address, required this.name});
  final String address;
  final String name;
}

/// `espface://<host>?id=..&name=..&proj=..`
DiscoveredDevice? parseQr(String text) {
  final u = Uri.tryParse(text.trim());
  if (u == null || u.scheme != 'espface' || u.host.isEmpty) return null;
  final host = u.hasPort ? '${u.host}:${u.port}' : u.host;
  final id = u.queryParameters['id'] ?? '';
  return DiscoveredDevice(id: id, name: u.queryParameters['name'] ?? host, host: host, proj: u.queryParameters['proj'], icon: u.queryParameters['icon']);
}
