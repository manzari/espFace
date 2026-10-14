import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_code_dart_scan/qr_code_dart_scan.dart';

import 'device.dart';
import 'devices_repository.dart';

/// Scans `espface://<host>?id=..&name=..` codes printed by the device (serial/web page).
/// Pure-Dart ZXing decoder over CameraX/AVFoundation: no ML Kit, so the APK stays FOSS-only.
class QrScanPage extends ConsumerStatefulWidget {
  const QrScanPage({super.key});
  @override
  ConsumerState<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends ConsumerState<QrScanPage> {
  bool _done = false;
  String? _last;

  void _onDetect(ScanResult r) {
    if (_done) return;
    final raw = r.text;
    final d = parseQr(raw);
    if (d == null) {
      if (raw != _last) setState(() => _last = raw);
      return;
    }
    _done = true;
    final saved = ref.read(devicesProvider.notifier).addDiscovered(d);
    context.go('/d/${Uri.encodeComponent(saved.key)}');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan device QR')),
        body: Stack(children: [
          QRCodeDartScanView(
            formats: const [BarcodeFormat.qrCode],
            onCapture: _onDetect,
            child: const SizedBox.expand(),
          ),
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
