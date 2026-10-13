import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../core/proto/messages.dart';
import '../../core/session/session.dart';
import '../render/ui_store.dart';

const otaChunkSize = 4096;

/// OTA push (PROTOCOL.md 4.14): `ota.begin` with size+md5, then WS binary frames of up to 4096 bytes.
class OtaPush extends ChangeNotifier {
  OtaPush({required this.session, required this.store});
  final Session session;
  final UiStore store;

  bool running = false;
  int sent = 0;
  int total = 0;
  String? error;
  bool _abort = false;

  double get sentFraction => total == 0 ? 0 : sent / total;

  Future<bool> run(Uint8List image) async {
    if (running) return false;
    running = true;
    error = null;
    sent = 0;
    total = image.length;
    _abort = false;
    notifyListeners();
    try {
      final ack = await _await('ota.begin', () => session.sys('ota.begin', {'size': image.length, 'md5': md5.convert(image).toString()}));
      if (ack == null) throw 'no reply to ota.begin';
      if (ack.ok != true) throw ack.msg ?? 'ota.begin refused';
      for (var off = 0; off < image.length; off += otaChunkSize) {
        if (_abort) throw 'aborted';
        final end = off + otaChunkSize > image.length ? image.length : off + otaChunkSize;
        if (!session.sendBinary(Uint8List.sublistView(image, off, end))) throw 'connection lost';
        sent = end;
        notifyListeners();
        if ((off ~/ otaChunkSize) % 8 == 7) await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final done = await _await('ota.done', () {}, timeout: const Duration(seconds: 60));
      if (done == null) throw 'no ota.done from device';
      if (done.ok != true) throw done.msg ?? 'device rejected the image';
      return true;
    } catch (e) {
      error = e.toString();
      return false;
    } finally {
      running = false;
      notifyListeners();
    }
  }

  void abort() {
    _abort = true;
    session.sys('ota.abort');
  }

  Future<SysMsg?> _await(String cmd, void Function() send, {Duration timeout = const Duration(seconds: 10)}) {
    final c = Completer<SysMsg?>();
    final key = store.listen('sys:$cmd');
    void onSys() {
      final m = store.lastSys;
      if (m != null && m.cmd == cmd && !c.isCompleted) c.complete(m);
    }

    key.addListener(onSys);
    send();
    return c.future.timeout(timeout, onTimeout: () => null).whenComplete(() => key.removeListener(onSys));
  }
}
