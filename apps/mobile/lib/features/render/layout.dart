import 'package:flutter/material.dart';

import 'common.dart';
import 'icons.dart';
import 'ui_store.dart';
import 'widgets/registry.dart';

/// Pages -> group cards -> rows -> widgets (PROTOCOL.md 5.1). Every card is a lazy sliver so a UI with hundreds
/// of widgets only builds what is on screen.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.page, this.wide = false});
  final PageLayout page;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final blocks = page.blocks;
    final list = CustomScrollView(
      slivers: [
        for (var i = 0; i < blocks.length; i++)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(12, i == 0 ? 12 : 0, 12, 12),
            sliver: blocks[i].kind == 'group' ? GroupCard(block: blocks[i]) : CardSliver(child: ItemsSliver(items: blocks[i].items)),
          ),
      ],
    );
    return wide ? Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: list)) : list;
  }
}

/// Card chrome (Material 3 colours and radius) around a sliver.
class CardSliver extends StatelessWidget {
  const CardSliver({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedSliver(
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(12)),
      sliver: SliverPadding(padding: const EdgeInsets.all(12), sliver: child),
    );
  }
}

/// Lazily built list of widgets and rows.
class ItemsSliver extends StatelessWidget {
  const ItemsSliver({super.key, required this.items});
  final List<LayoutItem> items;
  @override
  Widget build(BuildContext context) => SliverList.builder(
        itemCount: items.length,
        itemBuilder: (c, i) {
          final it = items[i];
          return it is WidgetItem ? WidgetView(it.id) : RowView(row: it as RowLayout);
        },
      );
}

/// Eager column of items (nested use: tests, small blocks).
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

/// Group card as a sliver: header (foldable) plus a lazy item list; hidden groups collapse to nothing.
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
          if (w == null || !w.vis) return const SliverToBoxAdapter(child: SizedBox.shrink());
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
          return CardSliver(
            child: SliverMainAxisGroup(slivers: [
              if (head != null) SliverToBoxAdapter(child: head),
              if (_open || !fold) ItemsSliver(items: widget.block.items),
            ]),
          );
        },
      );
}
