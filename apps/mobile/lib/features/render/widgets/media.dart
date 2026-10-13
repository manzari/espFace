import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/proto/messages.dart';
import '../../../core/proto/values.dart';
import '../common.dart';

class ImageWidget extends StatelessWidget {
  const ImageWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  Widget build(BuildContext context) {
    final src = w.src;
    final cs = Theme.of(context).colorScheme;
    return Frame(
      w: w,
      child: src == null || src.isEmpty
          ? Text('no source', style: TextStyle(color: cs.onSurfaceVariant))
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                src,
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => Text('image unavailable', style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            ),
    );
  }
}

/// MJPEG stream: reads the multipart body and shows each JPEG frame as it arrives.
class StreamWidget extends StatefulWidget {
  const StreamWidget(this.w, {super.key});
  final WidgetDef w;
  @override
  State<StreamWidget> createState() => _StreamWidgetState();
}

class _StreamWidgetState extends State<StreamWidget> {
  Uint8List? _frame;
  bool _error = false;
  HttpClient? _client;
  StreamSubscription? _sub;
  String? _src;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(StreamWidget old) {
    super.didUpdateWidget(old);
    if (widget.w.src != _src) _start();
  }

  Future<void> _start() async {
    await _stop();
    _src = widget.w.src;
    final src = _src;
    if (src == null || src.isEmpty) return;
    setState(() => _error = false);
    try {
      final client = HttpClient();
      _client = client;
      final res = await client.getUrl(Uri.parse(src)).then((r) => r.close());
      final buf = BytesBuilder(copy: false);
      _sub = res.listen((chunk) {
        buf.add(chunk);
        final frame = _extract(buf);
        if (frame != null && mounted) setState(() => _frame = frame);
      }, onError: (_) => _fail(), onDone: _fail, cancelOnError: true);
    } catch (_) {
      _fail();
    }
  }

  // Finds the last complete JPEG (FFD8 .. FFD9) in the buffer and drops everything before it.
  static Uint8List? _extract(BytesBuilder buf) {
    final bytes = buf.toBytes();
    var end = -1;
    for (var i = bytes.length - 2; i >= 0; i--) {
      if (bytes[i] == 0xff && bytes[i + 1] == 0xd9) {
        end = i + 2;
        break;
      }
    }
    if (end < 0) {
      if (bytes.length > 4 * 1024 * 1024) buf.clear();
      return null;
    }
    var start = -1;
    for (var i = end - 2; i >= 0; i--) {
      if (bytes[i] == 0xff && bytes[i + 1] == 0xd8) {
        start = i;
        break;
      }
    }
    buf.clear();
    buf.add(bytes.sublist(end));
    return start < 0 ? null : Uint8List.sublistView(bytes, start, end);
  }

  void _fail() {
    if (mounted) setState(() => _error = true);
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    _client?.close(force: true);
    _client = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final src = widget.w.src;
    return Frame(
      w: widget.w,
      child: src == null || src.isEmpty
          ? Text('no source', style: TextStyle(color: cs.onSurfaceVariant))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_frame != null) ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_frame!, gaplessPlayback: true, fit: BoxFit.contain)),
              if (_frame == null && !_error) Container(height: 120, alignment: Alignment.center, decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)), child: const CircularProgressIndicator()),
              if (_error) OutlinedButton.icon(onPressed: _start, icon: const Icon(Icons.refresh), label: const Text('Stream unavailable, retry')),
            ]),
    );
  }
}

/// Map with OSM tiles (the only non-release-check internet use, opt-in by the device UI) and markers from the value.
class MapWidget extends StatefulWidget {
  const MapWidget(this.w, {super.key});
  final WidgetDef w;

  static List<(LatLng, String?)> pointsOf(dynamic v) => [
        if (v is List)
          for (final p in v)
            if (p is List && p.length >= 2 && p[0] is num && p[1] is num) (LatLng(asNum(p[0]), asNum(p[1])), p.length > 2 ? asStr(p[2]) : null),
      ];

  @override
  State<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget> {
  final _ctl = MapController();
  String? _fitted;

  void _fit(List<(LatLng, String?)> pts) {
    final key = pts.map((p) => '${p.$1.latitude},${p.$1.longitude}').join(';');
    if (key == _fitted || pts.isEmpty) return;
    _fitted = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        if (pts.length == 1) {
          _ctl.move(pts.first.$1, widget.w.zoom.toDouble());
        } else {
          _ctl.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts.map((p) => p.$1).toList()), padding: const EdgeInsets.all(24)));
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueOf(
        id: widget.w.id,
        builder: (c, v) {
          final pts = MapWidget.pointsOf(v);
          _fit(pts);
          final cs = Theme.of(c).colorScheme;
          return Frame(
            w: widget.w,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: widget.w.sizeH ?? 220,
                child: FlutterMap(
                  mapController: _ctl,
                  options: MapOptions(initialCenter: pts.isNotEmpty ? pts.first.$1 : const LatLng(0, 0), initialZoom: pts.isNotEmpty ? widget.w.zoom.toDouble() : 2),
                  children: [
                    TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'dev.manzari.espface', errorTileCallback: (_, _, _) {}),
                    MarkerLayer(markers: [
                      for (final p in pts)
                        Marker(
                          point: p.$1,
                          width: 120,
                          height: 48,
                          alignment: Alignment.topCenter,
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.location_on, color: cs.error, size: 28),
                            if (p.$2 != null) Container(padding: const EdgeInsets.symmetric(horizontal: 4), color: cs.surface, child: Text(p.$2!, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                          ]),
                        ),
                    ]),
                    const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
                  ],
                ),
              ),
            ),
          );
        },
      );
}
