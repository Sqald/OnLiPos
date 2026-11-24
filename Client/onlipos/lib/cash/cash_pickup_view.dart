/// レジ金途中回収画面。
/// 営業中にレジ内の現金の一部を回収した際に金額と理由を記録し、
/// 回収レシートを印字する。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onlipos/ui/num_pad.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_header.dart';

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

  // 金額を3桁区切りの文字列に整形する
  String _formatCurrency(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );

  /// 入力内容を確認ダイアログで確認した上で途中回収を登録し、成功したら回収レシートを印字する
  Future<void> _submit() async {
    final amount = int.tryParse(_amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      showMessage(context, '回収金額を正しく入力してください', MessageType.error);
      return;
    }

    final ok = await showDialog<bool>(
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
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('やめる'),
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

    if (ok != true || !mounted) return;

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
        showMessage(
          context,
          '¥${_formatCurrency(amount)} を回収しました',
          MessageType.info,
        );
        Navigator.of(context).pop();
      }
    } else {
      final msg = result['message']?.toString() ?? 'エラーが発生しました';
      showMessage(context, msg, MessageType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.none,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
          textAlign: TextAlign.right,
          decoration: InputDecoration(labelText: '回収する金額', prefixText: '¥ '),
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _reasonController,
          decoration: const InputDecoration(
            labelText: '理由（なくても可）',
            hintText: '例: 金庫に移動',
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 64,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            child: _isLoading
                ? const CircularProgressIndicator()
                : Text('回収を記録する', style: const TextStyle(fontSize: 20)),
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppHeader(
        '途中回収',
        subtitle: 'レジから抜いて金庫などに移す金額を記録します。　担当: ${widget.employeeName}',
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: LayoutBuilder(
              builder: (context, box) {
                final pad = NumPad(
                  controller: _amountController,
                  showDoubleZero: true,
                  maxLength: 8,
                );
                if (box.maxWidth < 640) {
                  return Column(
                    children: [
                      SectionCard(child: fields),
                      const SizedBox(height: 12),
                      pad,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: SectionCard(child: fields)),
                    const SizedBox(width: 16),
                    SizedBox(width: 290, child: pad),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
