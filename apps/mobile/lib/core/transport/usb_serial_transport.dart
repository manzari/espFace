import 'dart:async';
import 'dart:typed_data';

import 'package:usb_serial/usb_serial.dart';

import 'stream_transport.dart';

/// USB OTG serial (Android only, `usb_serial`): 8N1 at [baud], port addressed by `vid:pid` (hex) as listed by [listPorts].
class UsbSerialTransport extends StreamTransport {
  UsbSerialTransport(this.port, {this.baud = 115200, Duration openTimeout = const Duration(seconds: 10)})
      : super(label: 'usb://$port@$baud', opener: () => _openPort(port, baud, openTimeout));

  final String port;
  final int baud;

  static const bauds = [9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600];

  static String portId(UsbDevice d) => '${(d.vid ?? 0).toRadixString(16).padLeft(4, '0')}:${(d.pid ?? 0).toRadixString(16).padLeft(4, '0')}';

  static String portName(UsbDevice d) => [d.productName, d.manufacturerName].where((s) => s != null && s.isNotEmpty).join(' ');

  static Future<List<UsbDevice>> listPorts() => UsbSerial.listDevices();

  static Future<ByteLink> _openPort(String port, int baud, Duration timeout) async {
    final devices = await UsbSerial.listDevices();
    final dev = devices.where((d) => portId(d) == port).firstOrNull;
    if (dev == null) throw StateError('USB device $port not attached');
    final p = await dev.create().timeout(timeout);
    if (p == null) throw StateError('no serial driver for $port');
    if (!await p.open().timeout(timeout)) throw StateError('USB permission denied or port busy');
    await p.setPortParameters(baud, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);
    await p.setDTR(true);
    await p.setRTS(true);
    return _UsbLink(p);
  }
}

class _UsbLink implements ByteLink {
  _UsbLink(this.port);
  final UsbPort port;
  @override
  Stream<Uint8List> get input => port.inputStream ?? const Stream.empty();
  @override
  Future<void> write(Uint8List data) => port.write(data);
  @override
  Future<void> close() async {
    await port.close();
  }
}
