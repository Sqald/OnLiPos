// 量り売り商品の重量(g)入力ダイアログ
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onlipos/product/product.dart';

/// 量り売り（計量）商品の重量(g)を入力するダイアログ。
/// 実機のはかりとは連携せず、レジ担当が読み取った重量を手入力する運用を想定する。
class WeightInputDialog extends StatefulWidget {
  final Product product;

  const WeightInputDialog({super.key, required this.product});

  @override
  State<WeightInputDialog> createState() => _WeightInputDialogState();
}

class _WeightInputDialogState extends State<WeightInputDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _fieldFocus = FocusNode();

  int get _grams => int.tryParse(_controller.text) ?? 0;
  int get _amount => (widget.product.price * _grams / 100).round();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fieldFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_grams <= 0) return;
    Navigator.of(context).pop(_grams);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product.name),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('100gあたり ¥${widget.product.price}（量り売り）'),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              focusNode: _fieldFocus,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '重量 (g)',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 24),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _confirm(),
            ),
            const SizedBox(height: 16),
            Text(
              '金額: ¥$_amount',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(onPressed: _confirm, child: const Text('確定')),
      ],
    );
  }
}
