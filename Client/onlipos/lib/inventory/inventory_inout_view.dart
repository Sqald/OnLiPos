import 'package:flutter/material.dart';
import 'package:onlipos/inventory/inventory_api.dart';
import 'package:onlipos/login/login_api.dart';
import 'package:onlipos/product/product.dart';
import 'package:onlipos/product/product_repository.dart';

class InventoryInOutView extends StatefulWidget {
  const InventoryInOutView({
    super.key,
  });

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

  final TextEditingController _employeeCodeController = TextEditingController();
  final TextEditingController _employeePinController = TextEditingController();

  final TextEditingController _janController = TextEditingController();
  final TextEditingController _quantityController =
      TextEditingController(text: '1');
  bool _isInbound = true;

  final List<InventoryMovementItem> _items = [];
  bool _isSubmitting = false;
  bool _isAuthenticating = false;
  int? _employeeId;
  String? _employeeName;

  @override
  void dispose() {
    _employeeCodeController.dispose();
    _employeePinController.dispose();
    _janController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _authenticateEmployee() async {
    final code = _employeeCodeController.text.trim();
    final pin = _employeePinController.text.trim();

    if (code.isEmpty || pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('担当者コードとパスワードを入力してください'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isAuthenticating = true;
    });

    try {
      final today = DateTime.now();
      final openDate =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final result = await LoginApi.userLogin(
        code: code,
        pin: pin,
        openDate: openDate,
      );

      if (result['success'] == true) {
        setState(() {
          _employeeId = result['employee_id'] as int?;
          _employeeName = result['employee_name'] as String?;
        });
        if (_employeeId == null || _employeeName == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('認証結果が不正です'),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('認証に成功しました: $_employeeName'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']?.toString() ?? '認証に失敗しました'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('認証中にエラーが発生しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
        });
      }
    }
  }

  Future<void> _addItem() async {
    if (_employeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('先に担当者IDとパスワードで認証してください'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final jan = _janController.text.trim();
    final qty = int.tryParse(_quantityController.text.trim());

    if (jan.isEmpty || qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('JANコードと正しい数量を入力してください'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final product = await _productRepository.findProductByCode(jan);
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('商品が見つかりません: $jan'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _items.add(InventoryMovementItem(
        product: product,
        quantity: qty,
        isInbound: _isInbound,
      ));
      _janController.clear();
      _quantityController.text = '1';
      _isInbound = true;
    });
  }

  Future<void> _submit() async {
    if (_employeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('先に担当者IDとパスワードで認証してください'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('入出荷明細がありません'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final movements = _items
        .map((e) => {
              'jan_code': e.product.code,
              'quantity': e.quantity,
              'direction': e.isInbound ? 'in' : 'out',
            })
        .toList();

    final result = await _inventoryApi.moveStocks(
      employeeId: _employeeId!,
      movements: movements,
    );

    setState(() {
      _isSubmitting = false;
    });

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('在庫の入出荷を登録しました'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _items.clear();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'エラーが発生しました'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('入出荷管理'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '入出荷管理を行う担当者のIDとパスワードを入力し、認証してください。',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _employeeCodeController,
                    decoration: const InputDecoration(
                      labelText: '担当者コード',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _employeePinController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'パスワード',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isAuthenticating ? null : _authenticateEmployee,
                  child: _isAuthenticating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('認証'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_employeeId != null && _employeeName != null)
              Text(
                '認証済み担当者: $_employeeName (ID: $_employeeId)',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 16),
            const Text(
              'JANコードと数量を入力し、入庫または出庫を選択して追加してください。',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _janController,
                    decoration: const InputDecoration(
                      labelText: 'JANコード',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '数量',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ToggleButtons(
                  isSelected: [_isInbound, !_isInbound],
                  onPressed: (index) {
                    setState(() {
                      _isInbound = index == 0;
                    });
                  },
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text('入庫'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text('出庫'),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addItem,
                  child: const Text('追加'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '入出荷明細',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _items.isEmpty
                  ? const Center(child: Text('明細はありません'))
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return Card(
                          child: ListTile(
                            title: Text(item.product.name),
                            subtitle: Text(
                                'JAN: ${item.product.code} / 数量: ${item.quantity} / ${item.isInbound ? '入庫' : '出庫'}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                setState(() {
                                  _items.removeAt(index);
                                });
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSubmitting ? '送信中...' : '入出荷登録'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

