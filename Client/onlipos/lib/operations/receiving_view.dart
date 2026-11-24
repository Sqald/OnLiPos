// 発注に対する入荷の登録（在庫操作の権限を持つ担当者）
import 'package:flutter/material.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:flutter/services.dart';
import 'package:onlipos/operations/common.dart';
import 'package:onlipos/sale/sale_extras_api.dart';

class ReceivingView extends StatelessWidget {
  const ReceivingView({super.key, required this.employeeId});

  final int employeeId;

  @override
  Widget build(BuildContext context) {
    return ReloadableList(
      title: '入荷',
      load: SaleExtrasApi.purchaseOrders,
      listKey: 'purchase_orders',
      emptyMessage: '入荷を待っている発注はありません',
      emptyIcon: Icons.local_shipping_outlined,
      itemBuilder: (context, item, reload) => ListTile(
        title: Text('${item['supplier_name']}（${item['number']}）'),
        subtitle: Text(
          '${item['items_count']}商品  入荷予定 ${item['expected_on'] ?? '-'}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _ReceiveView(
                orderId: item['id'] as int,
                employeeId: employeeId,
              ),
            ),
          );
          reload();
        },
      ),
    );
  }
}

class _ReceiveView extends StatefulWidget {
  const _ReceiveView({required this.orderId, required this.employeeId});

  final int orderId;
  final int employeeId;

  @override
  State<_ReceiveView> createState() => _ReceiveViewState();
}

class _ReceiveViewState extends State<_ReceiveView> {
  List<Map<String, dynamic>> _items = [];
  final Map<int, TextEditingController> _quantities = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _quantities.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final result = await SaleExtrasApi.purchaseOrder(widget.orderId);
    if (!mounted) return;
    if (result['success'] != true) return showResult(result, '');
    setState(() {
      _items =
          ((result['purchase_order'] as Map<String, dynamic>)['items']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>();
      for (final item in _items) {
        _quantities[item['id'] as int] = TextEditingController(
          text: item['remaining'].toString(),
        );
      }
    });
  }

  Future<void> _submit() async {
    if (!_quantities.values.any((c) => (int.tryParse(c.text) ?? 0) > 0)) {
      showMessage(context, '届いた数を入力してください', MessageType.error);
      return;
    }
    setState(() => _busy = true);
    final result = await SaleExtrasApi.receive(
      orderId: widget.orderId,
      employeeId: widget.employeeId,
      received: {
        for (final e in _quantities.entries)
          if ((int.tryParse(e.value.text) ?? 0) > 0)
            e.key.toString(): int.parse(e.value.text),
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    showResult(result, '入荷を登録しました');
    if (result['success'] == true) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader('入荷の登録', subtitle: '届いた数を入力してください'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final item in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  title: Text('${item['product_name']}'),
                  subtitle: Text(
                    '${item['product_code']}　発注 ${item['quantity']}　入荷済み ${item['received_quantity']}',
                  ),
                  trailing: SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _quantities[item['id'] as int],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: const InputDecoration(suffixText: '個'),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 60,
          child: ElevatedButton.icon(
            onPressed: _busy || _items.isEmpty ? null : _submit,
            icon: const Icon(Icons.check),
            label: const Text('入荷を登録する', style: TextStyle(fontSize: 20)),
          ),
        ),
      ),
    );
  }
}
