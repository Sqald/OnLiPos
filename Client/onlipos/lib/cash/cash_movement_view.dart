import 'package:flutter/material.dart';

import 'cash_log_api.dart';
import '../sale/escpos/lan_recipt_api.dart';

/// レジ入出金の種別（サーバーの CashMovement.kind と対応）
enum CashMovementKind {
  replenishment('replenishment', '釣銭補充', true, Icons.add_circle_outline),
  miscIn('misc_in', '雑入金', true, Icons.arrow_downward),
  miscOut('misc_out', '雑出金', false, Icons.arrow_upward),
  pickup('pickup', '途中回収', false, Icons.savings_outlined);

  final String value;
  final String label;
  final bool isInbound;
  final IconData icon;
  const CashMovementKind(this.value, this.label, this.isInbound, this.icon);
}

/// レジ入出金画面（途中回収画面の対称形）。
/// 釣銭補充・雑入金・雑出金・途中回収を記録し、理論在高に反映させる。
class CashMovementView extends StatefulWidget {
  final int employeeId;
  final String employeeName;

  const CashMovementView({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<CashMovementView> createState() => _CashMovementViewState();
}

class _CashMovementViewState extends State<CashMovementView> {
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  CashMovementKind _kind = CashMovementKind.replenishment;
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
      ).showSnackBar(const SnackBar(content: Text('金額を正しく入力してください')));
      return;
    }

    final directionLabel = _kind.isInbound ? '入金' : '出金';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_kind.label}の確認'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('担当者: ${widget.employeeName}'),
            const SizedBox(height: 8),
            Text(
              '$directionLabel金額: ¥${_formatCurrency(amount)}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (_reasonController.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('事由: ${_reasonController.text}'),
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
              backgroundColor: _kind.isInbound
                  ? Colors.teal[700]
                  : Colors.orange[800],
              foregroundColor: Colors.white,
            ),
            child: Text('${_kind.label}を実行'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);

    final result = await _api.cashMovement(
      employeeId: widget.employeeId,
      kind: _kind.value,
      amount: amount,
      reason: _reasonController.text.isEmpty ? null : _reasonController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      // ドロア開放（現金を実際に動かすため）
      ReceiptPrinter.openDrawer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_kind.label} ¥${_formatCurrency(amount)} を記録しました'),
        ),
      );
      Navigator.of(context).pop();
    } else {
      final msg = result['message']?.toString() ?? 'エラーが発生しました';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('レジ入出金')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '担当者: ${widget.employeeName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            const Text(
              '入出金の種別',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: CashMovementKind.values.map((kind) {
                final selected = _kind == kind;
                return ChoiceChip(
                  avatar: Icon(
                    kind.icon,
                    size: 20,
                    color: selected ? Colors.white : Colors.grey[700],
                  ),
                  label: Text(kind.label),
                  selected: selected,
                  selectedColor: kind.isInbound
                      ? Colors.teal[700]
                      : Colors.orange[800],
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : Colors.black87,
                    fontSize: 16,
                  ),
                  onSelected: (_) => setState(() => _kind = kind),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Text(
              '${_kind.isInbound ? '入金' : '出金'}金額（円）',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
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
              '事由（任意）',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '例: 釣銭補充 / 備品購入',
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
                  backgroundColor: _kind.isInbound
                      ? Colors.teal[700]
                      : Colors.orange[800],
                  foregroundColor: Colors.white,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        '${_kind.label}を実行',
                        style: const TextStyle(fontSize: 20),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
