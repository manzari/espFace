import 'dart:convert';

/// One result of [LineFramer.feed]: a complete line, or an oversize line that was discarded.
sealed class LineEvent {
  const LineEvent();
}

class LineText extends LineEvent {
  const LineText(this.text);
  final String text;
}

class LineOversize extends LineEvent {
  const LineOversize();
}

/// Splits a byte stream into `\n`-terminated lines (mirror of the firmware `LineFramer.h`): `\r` is dropped,
/// empty lines are skipped, a line longer than [cap] is discarded and reported once at its newline.
class LineFramer {
  LineFramer({this.cap = 2048});

  final int cap;
  final List<int> _buf = [];
  bool _over = false;

  List<LineEvent> feed(List<int> bytes) {
    final out = <LineEvent>[];
    for (final b in bytes) {
      if (b == 0x0d) continue;
      if (b == 0x0a) {
        if (_over) {
          _over = false;
          _buf.clear();
          out.add(const LineOversize());
        } else if (_buf.isNotEmpty) {
          out.add(LineText(utf8.decode(_buf, allowMalformed: true)));
          _buf.clear();
        }
        continue;
      }
      if (_over) continue;
      if (_buf.length >= cap) {
        _over = true;
        _buf.clear();
        continue;
      }
      _buf.add(b);
    }
    return out;
  }

  void reset() {
    _buf.clear();
    _over = false;
  }
}
