import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'device.dart';
import 'devices_repository.dart';

/// Scans `espface://<host>?id=..&name=..` codes printed by the device (serial/web page).
class QrScanPage extends ConsumerStatefulWidget {
  const QrScanPage({super.key});
  @override
  ConsumerState<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends ConsumerState<QrScanPage> {
  bool _done = false;
  String? _last;

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final d = parseQr(raw);
      if (d == null) {
        if (raw != _last) setState(() => _last = raw);
        continue;
      }
      _done = true;
      final saved = ref.read(devicesProvider.notifier).addDiscovered(d);
      context.go('/d/${Uri.encodeComponent(saved.key)}');
      return;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan device QR')),
        body: Stack(children: [
          MobileScanner(onDetect: _onDetect),
          if (_last != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Material(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
                child: Padding(padding: const EdgeInsets.all(12), child: Text('Not an espFace code: $_last', style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer))),
              ),
            ),
        ]),
      );
}
