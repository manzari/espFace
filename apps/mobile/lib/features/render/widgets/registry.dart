import 'package:flutter/material.dart';

import '../../../core/proto/messages.dart';
import '../common.dart';
import 'basic.dart';
import 'chart.dart';
import 'gauge.dart';
import 'inputs.dart';
import 'joystick.dart';
import 'log_table.dart';
import 'media.dart';

typedef WidgetBuilderFor = Widget Function(WidgetDef w);

/// One Flutter widget per protocol `ty`; layout types (group, page, row) are handled by the layout.
final Map<String, WidgetBuilderFor> widgetRegistry = {
  'label': (w) => LabelWidget(w),
  'button': (w) => ButtonWidget(w),
  'switch': (w) => SwitchWidget(w),
  'slider': (w) => SliderWidget(w),
  'number': (w) => NumberWidget(w),
  'text': (w) => TextWidget(w),
  'textarea': (w) => TextWidget(w, multiline: true),
  'select': (w) => SelectWidget(w),
  'flags': (w) => FlagsWidget(w),
  'color': (w) => ColorWidget(w),
  'datetime': (w) => DatetimeWidget(w),
  'joystick': (w) => JoystickWidget(w),
  'dpad': (w) => DpadWidget(w),
  'gauge': (w) => GaugeWidget(w),
  'progress': (w) => ProgressWidget(w),
  'display': (w) => DisplayWidget(w),
  'led': (w) => LedWidget(w),
  'chart': (w) => ChartWidget(w),
  'log': (w) => LogWidget(w),
  'table': (w) => TableWidget(w),
  'image': (w) => ImageWidget(w),
  'stream': (w) => StreamWidget(w),
  'clock': (w) => ClockWidget(w),
  'map': (w) => MapWidget(w),
  'textblock': (w) => TextblockWidget(w),
  'header': (w) => HeaderWidget(w),
  'spacer': (w) => SpacerWidget(w),
  'group': (w) => const SizedBox.shrink(),
  'page': (w) => const SizedBox.shrink(),
  'row': (w) => const SizedBox.shrink(),
};

/// Renders one widget id; rebuilds only when its own definition changes (`prop`) or it is hidden.
class WidgetView extends StatelessWidget {
  const WidgetView(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context) => StoreListener(
        keyName: 'w:$id',
        builder: (c) {
          final w = c.store.widgets[id];
          if (w == null || !w.vis) return const SizedBox.shrink();
          final b = widgetRegistry[w.ty];
          return KeyedSubtree(key: ValueKey('w:$id'), child: b != null ? b(w) : UnsupportedWidget(w));
        },
      );
}
