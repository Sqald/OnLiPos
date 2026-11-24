// 会計の取消（VOID）。精算前の会計だけを、返品と同じ2名の認証で取り消す。
import 'package:flutter/material.dart';
import 'package:onlipos/api/pos_api_client.dart';
import 'package:onlipos/login/employee_auth_dialog.dart';
import 'package:onlipos/operations/common.dart';
import 'package:onlipos/sale/sale_extras_api.dart';

class VoidSaleView extends StatefulWidget {
  const VoidSaleView({super.key, required this.employeeId});

  /// 売上一覧を閲覧する担当者（view_sales 権限で認証済み）
  final int employeeId;

  @override
  State<VoidSaleView> createState() => _VoidSaleViewState();
}

class _VoidSaleViewState extends State<VoidSaleView> {
  Future<void> _void(Map<String, dynamic> sale, VoidCallback reload) async {
    final reason = await _askReason(sale);
    if (reason == null || reason.isEmpty || !mounted) return;

    final first = await showEmployeeAuthDialog(
      context,
      title: '取消の承認（1人目）',
      permission: 'refund',
    );
    if (first == null || !mounted) return;
    final second = await showEmployeeAuthDialog(
      context,
      title: '取消の承認（2人目）',
      permission: 'refund',
    );
    if (second == null || !mounted) return;

    final result = await SaleExtrasApi.voidSale(
      saleId: sale['id'] as int,
      employeeIds: [first.id, second.id],
      reason: reason,
    );
    OperatorApprovals.clear('refund');
    showResult(result, '会計を取り消しました。お客様への返金を行ってください');
    reload();
  }

  Future<String?> _askReason(Map<String, dynamic> sale) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${sale['receipt_number']}  ¥${sale['total_amount']}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '取消の理由'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('戻る'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('取消に進む'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return ReloadableList(
      title: '会計の取消（本日）',
      load: () =>
          SaleExtrasApi.sales(employeeId: widget.employeeId, date: today),
      listKey: 'sales',
      emptyMessage: '本日の会計はありません',
      itemBuilder: (context, sale, reload) => ListTile(
        title: Text('${sale['created_at']}  ¥${sale['total_amount']}'),
        subtitle: Text('${sale['receipt_number']}  ${sale['employee_name']}'),
        trailing: sale['status'] == 'voided'
            ? const Text('取消済み')
            : OutlinedButton(
                onPressed: sale['voidable'] == true
                    ? () => _void(sale, reload)
                    : null,
                child: const Text('取消'),
              ),
      ),
    );
  }
}
