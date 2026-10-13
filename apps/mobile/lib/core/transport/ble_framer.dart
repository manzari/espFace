import 'dart:typed_data';

/// GATT packet layout (PROTOCOL.md 2, firmware `BleFramer.h`): `[seq:1][flags:1][payload]`.
/// flags bit0 = last chunk of the message, bit1 = first chunk; seq wraps 255 -> 0 per direction.
const int bleFlagLast = 1;
const int bleFlagFirst = 2;

/// Firmware limits: `ESPFACE_MAX_MSG` (C2D message) and `ESPFACE_BLE_MTU`.
const int bleMaxMessage = 2048;
const int bleMaxMtu = 512;
const int bleMinMtu = 23;

/// Client -> device: splits one message into packets of `mtu - 3` payload bytes (mirror of `BleChunker`).
class BleChunker {
  BleChunker({int mtu = bleMinMtu}) {
    setMtu(mtu);
  }

  int _max = 20;
  int _seq = 0;
  bool _first = true;

  void setMtu(int mtu) => _max = mtu.clamp(bleMinMtu, bleMaxMtu) - 3;

  int get payloadMax => _max;
  int get seq => _seq;

  void reset() => _first = true;

  /// Packets for one whole message; an empty message still produces one (first|last) packet.
  List<Uint8List> chunk(List<int> message) {
    final out = <Uint8List>[];
    var off = 0;
    do {
      final take = (message.length - off).clamp(0, _max);
      final last = off + take >= message.length;
      final pkt = Uint8List(2 + take);
      pkt[0] = _seq;
      _seq = (_seq + 1) & 0xff;
      pkt[1] = (last ? bleFlagLast : 0) | (_first ? bleFlagFirst : 0);
      pkt.setRange(2, 2 + take, message, off);
      out.add(pkt);
      off += take;
      _first = last;
      if (last) break;
    } while (true);
    return out;
  }
}

enum BleFeed { none, message, dropped, oversize }

/// Device -> client: rebuilds messages (mirror of `BleReassembler`). A seq gap or a stray continuation
/// drops the partial message, a repeated seq is ignored, an oversize message is skipped up to its last chunk.
class BleReassembler {
  BleReassembler({this.cap = bleMaxMessage});

  final int cap;
  final BytesBuilder _buf = BytesBuilder();
  Uint8List? _ready;
  int _expect = 0;
  bool _open = false;
  bool _skip = false;

  /// The last complete message (valid until the next [feed] that returns [BleFeed.message]).
  Uint8List? get message => _ready;
  bool get partial => _open;

  /// Bytes of the message being assembled.
  int get partialLength => _open ? _buf.length : 0;

  BleFeed feed(List<int> pkt) {
    if (pkt.length < 2) return BleFeed.dropped;
    final seq = pkt[0], flags = pkt[1];
    if (flags & bleFlagFirst != 0) {
      _open = true;
      _skip = false;
      _buf.clear();
    } else if (_skip) {
      if (seq == _expect) {
        _expect = (_expect + 1) & 0xff;
        if (flags & bleFlagLast != 0) _skip = false;
      }
      return BleFeed.none;
    } else if (!_open) {
      return BleFeed.dropped;
    } else if (seq == (_expect - 1) & 0xff) {
      return BleFeed.none;
    } else if (seq != _expect) {
      _open = false;
      _buf.clear();
      return BleFeed.dropped;
    }
    _expect = (seq + 1) & 0xff;
    final len = pkt.length - 2;
    if (_buf.length + len > cap) {
      _open = false;
      _skip = flags & bleFlagLast == 0;
      _buf.clear();
      return BleFeed.oversize;
    }
    _buf.add(pkt.sublist(2));
    if (flags & bleFlagLast != 0) {
      _open = false;
      _ready = _buf.takeBytes();
      return BleFeed.message;
    }
    return BleFeed.none;
  }

  void reset() {
    _open = _skip = false;
    _buf.clear();
    _ready = null;
  }
}
