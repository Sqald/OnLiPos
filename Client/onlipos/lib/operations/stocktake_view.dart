// 棚卸の数量登録（在庫操作の権限を持つ担当者）
import 'package:flutter/material.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_header.dart';
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
      emptyMessage: '実施中の棚卸はありません。管理画面の「棚卸」で始めてください',
      emptyIcon: Icons.checklist,
      itemBuilder: (context, item, reload) => ListTile(
        title: Text(item['name']?.toString() ?? ''),
        subtitle: Text('数えた商品 ${item['items_count']}件'),
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
    if (_code.text.trim().isEmpty || quantity == null) {
      showMessage(context, '商品コードと数を入力してください', MessageType.error);
      return;
    }
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
          '${result['product_name']}　${result['counted_quantity']}個',
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
      appBar: AppHeader('棚卸', subtitle: widget.name),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _code,
                    focusNode: _codeFocus,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '商品コード（バーコード）',
                      prefixIcon: Icon(Icons.qr_code_scanner),
                    ),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _quantity,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: '数えた数',
                      suffixText: '個',
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('足す')),
                    ButtonSegment(value: false, label: Text('置き換える')),
                  ],
                  selected: {_add},
                  onSelectionChanged: (v) => setState(() => _add = v.first),
                ),
                ElevatedButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.check),
                  label: const Text('登録する'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _history.isEmpty
                ? const EmptyState(
                    icon: Icons.checklist,
                    title: '商品を数えて登録してください',
                    message: '同じ商品を別の場所で見つけたら「足す」で登録します',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _history.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.check_circle,
                          color: AppColors.success,
                        ),
                        title: Text(_history[i]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
