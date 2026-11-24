// 商品オプション（トッピング・サイズなど）の選択ダイアログ
import 'package:flutter/material.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/product/product.dart';

/// 選択したオプションを返す。キャンセル時は null
Future<List<OptionItem>?> showOptionSelectDialog(
  BuildContext context,
  Product product,
) {
  return showDialog<List<OptionItem>>(
    context: context,
    builder: (_) => _OptionSelectDialog(product: product),
  );
}

class _OptionSelectDialog extends StatefulWidget {
  const _OptionSelectDialog({required this.product});

  final Product product;

  @override
  State<_OptionSelectDialog> createState() => _OptionSelectDialogState();
}

class _OptionSelectDialogState extends State<_OptionSelectDialog> {
  final Set<int> _selected = {};

  int _count(OptionGroup group) =>
      group.items.where((i) => _selected.contains(i.id)).length;

  bool get _valid => widget.product.optionGroups.every((g) {
    final count = _count(g);
    return count >= g.minSelect && count <= g.maxSelect;
  });

  void _toggle(OptionGroup group, OptionItem item) {
    setState(() {
      if (_selected.remove(item.id)) return;
      // 1つだけ選ぶグループは、選び直すと入れ替わる
      if (group.maxSelect == 1) {
        _selected.removeAll(group.items.map((i) => i.id));
      }
      if (_count(group) < group.maxSelect) _selected.add(item.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.product.optionGroups;
    return AlertDialog(
      title: Text(widget.product.name),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final group in groups) ...[
              Text(
                group.minSelect == 0
                    ? '${group.name}（${group.maxSelect}つまで）'
                    : '${group.name}（${group.minSelect}〜${group.maxSelect}つ選んでください）',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in group.items)
                    FilterChip(
                      label: Text(
                        item.price > 0
                            ? '${item.name} +${yen(item.price)}'
                            : item.name,
                      ),
                      selected: _selected.contains(item.id),
                      onSelected: (_) => _toggle(group, item),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('やめる'),
        ),
        ElevatedButton(
          onPressed: _valid
              ? () => Navigator.of(context).pop(
                  groups
                      .expand((g) => g.items)
                      .where((i) => _selected.contains(i.id))
                      .toList(),
                )
              : null,
          child: const Text('登録する'),
        ),
      ],
    );
  }
}
