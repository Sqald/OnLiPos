// 棚卸の数量登録（在庫操作の権限を持つ担当者）
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onlipos/operations/common.dart';
import 'package:onlipos/sale/sale_extras_api.dart';

class StocktakeView extends StatelessWidget {
  const StocktakeView({super.key, required this.employeeId});

  final int employeeId;

  @override
  Widget build(BuildContext context) {
    return ReloadableList(
      title: '棚卸',
      load: SaleExtrasApi.stocktakes,
      listKey: 'stocktakes',
      emptyMessage: '実施中の棚卸はありません（管理画面で開始してください）',
      itemBuilder: (context, item, reload) => ListTile(
        title: Text(item['name']?.toString() ?? ''),
        subtitle: Text('登録済み ${item['items_count']}商品'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _StocktakeCountView(
                stocktakeId: item['id'] as int,
                name: item['name'].toString(),
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

class _StocktakeCountView extends StatefulWidget {
  const _StocktakeCountView({
    required this.stocktakeId,
    required this.name,
    required this.employeeId,
  });

  final int stocktakeId;
  final String name;
  final int employeeId;

  @override
  State<_StocktakeCountView> createState() => _StocktakeCountViewState();
}

class _StocktakeCountViewState extends State<_StocktakeCountView> {
  final _code = TextEditingController();
  final _quantity = TextEditingController();
  final _codeFocus = FocusNode();
  final List<String> _history = [];
  bool _add = true;

  @override
  void dispose() {
    _code.dispose();
    _quantity.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final quantity = int.tryParse(_quantity.text);
    if (_code.text.trim().isEmpty || quantity == null) return;
    final result = await SaleExtrasApi.countStock(
      stocktakeId: widget.stocktakeId,
      employeeId: widget.employeeId,
      code: _code.text.trim(),
      quantity: quantity,
      add: _add,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      setState(
        () => _history.insert(
          0,
          '${result['product_name']}: ${result['counted_quantity']}',
        ),
      );
      _code.clear();
      _quantity.clear();
      _codeFocus.requestFocus();
    } else {
      showResult(result, '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('棚卸: ${widget.name}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _code,
              focusNode: _codeFocus,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: '商品コード（JAN）'),
            ),
            TextField(
              controller: _quantity,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: '数量'),
              onSubmitted: (_) => _submit(),
            ),
            SwitchListTile(
              title: const Text('加算する（オフにすると上書き）'),
              value: _add,
              onChanged: (v) => setState(() => _add = v),
            ),
            ElevatedButton(onPressed: _submit, child: const Text('登録')),
            const Divider(),
            Expanded(
              child: ListView(
                children: [for (final h in _history) ListTile(title: Text(h))],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
