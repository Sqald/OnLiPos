import 'package:material_ui/material_ui.dart';
import 'package:onlipos/ui/common.dart';
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

  // 定価/店舗売価ボタンから選択（値引き理由なし）
  void _select(int price) {
    Navigator.of(context).pop((price: price, reason: null as String?));
  }

  // 手動入力した価格・理由を確定して呼び出し元に返す
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
      title: const Text('値段を変える'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _product.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              if (_product.hasStorePrice)
                OutlinedButton(
                  onPressed: () => _select(_product.listPrice),
                  child: Text('基本価格 ${yen(_product.listPrice)} にする'),
                ),
              if (_product.hasStorePrice) const SizedBox(height: 6),
              OutlinedButton(
                onPressed: () => _select(_product.price),
                child: Text(
                  _product.hasStorePrice
                      ? 'この店舗の価格 ${yen(_product.price)} にする'
                      : '元の値段 ${yen(_product.price)} にする',
                ),
              ),
              const Divider(height: 24),
              CheckboxListTile(
                value: _isManual,
                onChanged: (v) => setState(() => _isManual = v ?? false),
                title: const Text('金額を入力して変える'),
                subtitle: const Text('会計のときに、値引きできる人の確認が必要です'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              if (_isManual) ...[
                TextField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '新しい値段',
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
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('やめる'),
        ),
        if (_isManual)
          ElevatedButton(onPressed: _applyManual, child: const Text('この値段にする')),
      ],
    );
  }
}
