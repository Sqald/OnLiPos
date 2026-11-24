/// 入出荷管理画面。
/// 担当者を認証した上でJANコードと数量を明細として積み上げ、
/// まとめてサーバーへ送信して店舗在庫を入庫/出庫する。
library;

import 'package:flutter/material.dart';
import 'package:onlipos/sale/cart_panel.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:onlipos/login/operator_sign_in_panel.dart';
import 'package:onlipos/inventory/inventory_api.dart';
import 'package:onlipos/product/product.dart';
import 'package:onlipos/product/product_repository.dart';

class InventoryInOutView extends StatefulWidget {
  const InventoryInOutView({super.key});

  @override
  State<InventoryInOutView> createState() => _InventoryInOutViewState();
}

class InventoryMovementItem {
  final Product product;
  int quantity;
  bool isInbound; // true: 入庫, false: 出庫

  InventoryMovementItem({
    required this.product,
    this.quantity = 1,
    this.isInbound = true,
  });
}

class _InventoryInOutViewState extends State<InventoryInOutView> {
  final _productRepository = ProductRepository();
  final _inventoryApi = InventoryApi();

  final TextEditingController _janController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController(
    text: '1',
  );
  bool _isInbound = true;

  final List<InventoryMovementItem> _items = [];
  bool _isSubmitting = false;
  final _janFocus = FocusNode();
  int? _employeeId;
  String? _employeeName;

  @override
  void dispose() {
    _janController.dispose();
    _janFocus.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  /// JANコードから商品を検索し、入力された数量・入出庫区分とともに明細一覧へ追加する
  Future<void> _addItem() async {
    final jan = _janController.text.trim();
    final qty = int.tryParse(_quantityController.text.trim());

    if (jan.isEmpty || qty == null || qty <= 0) {
      showMessage(context, '商品コードと数量を入力してください', MessageType.error);
      return;
    }

    final product = await _productRepository.findProductByCode(jan);
    if (!mounted) return;
    if (product == null) {
      showMessage(context, '商品が見つかりません: $jan', MessageType.error);
      return;
    }

    setState(() {
      _items.add(
        InventoryMovementItem(
          product: product,
          quantity: qty,
          isInbound: _isInbound,
        ),
      );
      _janController.clear();
      _quantityController.text = '1';
    });
    _janFocus.requestFocus();
  }

  /// 積み上げた入出荷明細をまとめてサーバーへ送信し、成功したら明細をクリアする
  Future<void> _submit() async {
    if (_items.isEmpty) {
      showMessage(context, '商品を追加してください', MessageType.error);
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final movements = _items
        .map(
          (e) => {
            'jan_code': e.product.code,
            'quantity': e.quantity,
            'direction': e.isInbound ? 'in' : 'out',
          },
        )
        .toList();

    final result = await _inventoryApi.moveStocks(
      employeeId: _employeeId!,
      movements: movements,
    );
    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
    });

    if (result['success'] == true) {
      showMessage(context, '入出庫を登録しました', MessageType.success);
      setState(() {
        _items.clear();
      });
    } else {
      showMessage(
        context,
        result['message']?.toString() ?? 'エラーが発生しました',
        MessageType.error,
      );
    }
  }

  // 担当者の確認 → 商品と数量を足していく → まとめて登録
  @override
  Widget build(BuildContext context) {
    if (_employeeId == null) {
      return Scaffold(
        appBar: const AppHeader('入出庫'),
        body: OperatorSignInPanel(
          icon: Icons.inventory_2_outlined,
          message: '在庫を増やす・減らすには、「在庫操作」の権限を持つ人の確認が必要です。',
          permission: 'inventory',
          onAuthenticated: (id, name) => setState(() {
            _employeeId = id;
            _employeeName = name;
          }),
        ),
      );
    }
    return Scaffold(
      appBar: AppHeader('入出庫', subtitle: '担当: ${_employeeName ?? ''}'),
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
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.add),
                      label: Text('入庫（増やす）'),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.remove),
                      label: Text('出庫（減らす）'),
                    ),
                  ],
                  selected: {_isInbound},
                  onSelectionChanged: (v) =>
                      setState(() => _isInbound = v.first),
                ),
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _janController,
                    focusNode: _janFocus,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '商品コード（バーコード）',
                      prefixIcon: Icon(Icons.qr_code_scanner),
                    ),
                    onSubmitted: (_) => _addItem(),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: '数量',
                      suffixText: '個',
                    ),
                    onSubmitted: (_) => _addItem(),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('一覧に足す'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _items.isEmpty
                ? const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: '商品を足してください',
                    message: 'バーコードを読み取るか、商品コードを入力します',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return Card(
                        child: ListTile(
                          leading: StatusBadge(
                            item.isInbound ? '入庫' : '出庫',
                            type: item.isInbound
                                ? MessageType.success
                                : MessageType.warning,
                          ),
                          title: Text(item.product.name),
                          subtitle: Text(item.product.code),
                          trailing: QuantityStepper(
                            quantity: item.quantity,
                            removeOnMinus: item.quantity <= 1,
                            onMinus: () => setState(() {
                              if (item.quantity > 1) {
                                item.quantity--;
                              } else {
                                _items.removeAt(index);
                              }
                            }),
                            onPlus: () => setState(() => item.quantity++),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              height: 64,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting || _items.isEmpty ? null : _submit,
                icon: const Icon(Icons.check),
                label: Text(
                  _isSubmitting ? '登録しています…' : '${_items.length}件を登録する',
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
