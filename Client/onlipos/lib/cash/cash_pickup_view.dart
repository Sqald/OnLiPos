import 'package:flutter/material.dart';

import 'cash_log_api.dart';
import '../sale/escpos/lan_recipt_api.dart';

class CashPickupView extends StatefulWidget {
  final int employeeId;
  final String employeeName;

  const CashPickupView({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<CashPickupView> createState() => _CashPickupViewState();
}

class _CashPickupViewState extends State<CashPickupView> {
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _isLoading = false;
  final _api = CashLogApi();

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  String _formatCurrency(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );

  Future<void> _submit() async {
    final amount = int.tryParse(_amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('回収金額を正しく入力してください')));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('途中回収の確認'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('担当者: ${widget.employeeName}'),
            const SizedBox(height: 8),
            Text(
              '回収金額: ¥${_formatCurrency(amount)}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (_reasonController.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('理由: ${_reasonController.text}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[800],
              foregroundColor: Colors.white,
            ),
            child: const Text('回収実行'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);

    final result = await _api.cashPickup(
      employeeId: widget.employeeId,
      amount: amount,
      reason: _reasonController.text.isEmpty ? null : _reasonController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      ReceiptPrinter.printPickupReceipt(
        pickupAmount: amount,
        employeeName: widget.employeeName,
        reason: _reasonController.text.isEmpty ? null : _reasonController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('¥${_formatCurrency(amount)} を回収しました')),
        );
        Navigator.of(context).pop();
      }
    } else {
      final msg = result['message']?.toString() ?? 'エラーが発生しました';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('レジ金 途中回収')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '担当者: ${widget.employeeName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            const Text(
              '回収金額（円）',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixText: '¥',
                hintText: '例: 10000',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            const Text(
              '回収理由（任意）',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '例: 金庫に移動',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[800],
                  foregroundColor: Colors.white,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('途中回収を実行', style: TextStyle(fontSize: 20)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
