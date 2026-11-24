/// レジ入出金画面と、その種別を表すenum定義。
/// 釣銭補充・雑入金・雑出金・途中回収を記録し、サーバー側の理論在高に反映させる。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onlipos/ui/num_pad.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_header.dart';

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

  // 金額を3桁区切りの文字列に整形する
  String _formatCurrency(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );

  /// 入力内容を確認ダイアログで確認した上でレジ入出金を登録し、成功したらドロアを開放する
  Future<void> _submit() async {
    final amount = int.tryParse(_amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      showMessage(context, '金額を正しく入力してください', MessageType.error);
      return;
    }

    final directionLabel = _kind.isInbound ? '入金' : '出金';
    final ok = await showDialog<bool>(
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
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('やめる'),
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

    if (ok != true || !mounted) return;

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
      showMessage(
        context,
        '${_kind.label} ¥${_formatCurrency(amount)} を記録しました',
        MessageType.info,
      );
      Navigator.of(context).pop();
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
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final kind in CashMovementKind.values)
              ChoiceChip(
                avatar: Icon(kind.icon, size: 20),
                showCheckmark: false,
                label: Text(kind.label),
                selected: _kind == kind,
                onSelected: (_) => setState(() => _kind = kind),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.none,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
          textAlign: TextAlign.right,
          decoration: InputDecoration(
            labelText: _kind.isInbound ? '入れる金額' : '出す金額',
            prefixText: '¥ ',
          ),
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _reasonController,
          decoration: const InputDecoration(
            labelText: '理由（なくても可）',
            hintText: '例: 釣銭の補充 / 備品の購入',
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 64,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            child: _isLoading
                ? const CircularProgressIndicator()
                : Text(
                    '${_kind.label}を記録する',
                    style: const TextStyle(fontSize: 20),
                  ),
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppHeader(
        '入出金',
        subtitle: 'レジに現金を足したり、出したりした記録をします。　担当: ${widget.employeeName}',
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
