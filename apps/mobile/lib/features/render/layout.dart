import 'package:flutter/material.dart';

import 'common.dart';
import 'icons.dart';
import 'ui_store.dart';
import 'widgets/registry.dart';

/// Pages -> group cards -> rows -> widgets (PROTOCOL.md 5.1).
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.page, this.wide = false});
  final PageLayout page;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final blocks = page.blocks;
    final list = ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: blocks.length,
      itemBuilder: (c, i) {
        final b = blocks[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: b.kind == 'group' ? GroupCard(block: b) : Card(child: Padding(padding: const EdgeInsets.all(12), child: ItemsColumn(items: b.items))),
        );
      },
    );
    return wide ? Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: list)) : list;
  }
}

class ItemsColumn extends StatelessWidget {
  const ItemsColumn({super.key, required this.items});
  final List<LayoutItem> items;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [for (final it in items) if (it is WidgetItem) WidgetView(it.id) else RowView(row: it as RowLayout)],
      );
}

class RowView extends StatelessWidget {
  const RowView({super.key, required this.row});
  final RowLayout row;
  @override
  Widget build(BuildContext context) => StoreListener(
        keyName: 'w:${row.id}',
        builder: (c) {
          final w = c.store.widgets[row.id];
          if (w != null && !w.vis) return const SizedBox.shrink();
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < row.items.length; i++)
                Expanded(
                  flex: ((c.store.widgets[row.items[i]]?.sizeW ?? 1) * 100).round().clamp(1, 100000),
                  child: Padding(padding: EdgeInsets.only(left: i == 0 ? 0 : 8), child: WidgetView(row.items[i])),
                ),
            ],
          );
        },
      );
}

class GroupCard extends StatefulWidget {
  const GroupCard({super.key, required this.block});
  final Block block;
  @override
  State<GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<GroupCard> {
  bool _open = true;

  @override
  Widget build(BuildContext context) => StoreListener(
        keyName: 'w:${widget.block.id}',
        builder: (c) {
          final w = c.store.widgets[widget.block.id];
          if (w == null || !w.vis) return const SizedBox.shrink();
          final fold = w.fold;
          final theme = Theme.of(c);
          final head = (w.lbl != null || w.icon != null)
              ? InkWell(
                  onTap: fold ? () => setState(() => _open = !_open) : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      if (w.icon != null) ...[Icon(iconFor(w.icon), size: 18, color: theme.colorScheme.primary), const SizedBox(width: 6)],
                      Expanded(child: Text(w.lbl ?? '', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary))),
                      if (fold) Icon(_open ? Icons.expand_less : Icons.expand_more),
                    ]),
                  ),
                )
              : null;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                ?head,
                if (_open || !fold) ItemsColumn(items: widget.block.items),
              ]),
            ),
          );
        },
      );
}
