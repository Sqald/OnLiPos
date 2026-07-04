import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onlipos/product/product.dart';

/// 価格変更ダイアログ。定価/店舗売価のボタンと手動値引き入力欄を提供する。
/// 戻り値: (price: 選択価格, reason: 値引き理由 or null)
class PriceEditDialog extends StatefulWidget {
  final Product product;

  const PriceEditDialog({super.key, required this.product});

  @override
  State<PriceEditDialog> createState() => _PriceEditDialogState();
}

class _PriceEditDialogState extends State<PriceEditDialog> {
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  bool _isManual = false;

  Product get _product => widget.product;

  @override
  void initState() {
    super.initState();
    _priceController.text = '${_product.price}';
  }

  @override
  void dispose() {
    _priceController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _select(int price) {
    Navigator.of(context).pop((price: price, reason: null as String?));
  }

  void _applyManual() {
    final p = int.tryParse(_priceController.text);
    if (p == null || p < 0) return;
    final reason = _reasonController.text.trim().isEmpty
        ? null
        : _reasonController.text.trim();
    Navigator.of(context).pop((price: p, reason: reason));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('価格変更'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _product.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (_product.hasStorePrice)
              OutlinedButton(
                onPressed: () => _select(_product.listPrice),
                child: Text('定価  ¥${_product.listPrice}'),
              ),
            if (_product.hasStorePrice) const SizedBox(height: 6),
            OutlinedButton(
              onPressed: () => _select(_product.price),
              child: Text(
                _product.hasStorePrice
                    ? '店舗売価  ¥${_product.price}'
                    : '元の価格  ¥${_product.price}',
              ),
            ),
            const Divider(height: 24),
            CheckboxListTile(
              value: _isManual,
              onChanged: (v) => setState(() => _isManual = v ?? false),
              title: const Text('手動値引き'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            if (_isManual) ...[
              TextField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '値引き後の価格',
                  prefixText: '¥',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: '理由（例: 賞味期限値引き）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        if (_isManual)
          ElevatedButton(onPressed: _applyManual, child: const Text('適用')),
      ],
    );
  }
}
