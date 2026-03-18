import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onlipos/login/operator_input_view.dart';
import 'package:onlipos/product/product.dart';
import 'package:onlipos/product/product_repository.dart';
import 'package:onlipos/sale/payment_view.dart';

class SaleScanView extends StatefulWidget {
  final String operatorName;

  const SaleScanView({super.key, required this.operatorName});

  @override
  State<SaleScanView> createState() => _SaleScanViewState();
}

class ScannedItem {
  final Product product;
  int quantity;

  ScannedItem({required this.product, this.quantity = 1});
}


class _SaleScanViewState extends State<SaleScanView> {
  final FocusNode _focusNode = FocusNode();

  final ProductRepository _productRepository = ProductRepository();
  final List<ScannedItem> _scannedItems = [];
  int _totalItems = 0;
  int _totalAmount = 0;
  String _barcodeBuffer = '';

  @override
  void initState() {
    super.initState();
    // Ensure the focus is requested after the first frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_focusNode);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _onBarcodeScanned(String barcode) async {
    if (barcode.isEmpty) return;

    final product = await _productRepository.findProductByCode(barcode);
    if (product != null) {
      setState(() {
        final existingItemIndex = _scannedItems.indexWhere((item) => item.product.code == barcode);
        if (existingItemIndex != -1) {
          _scannedItems[existingItemIndex].quantity++;
        } else {
          _scannedItems.insert(0, ScannedItem(product: product));
        }
        _calculateTotals();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('商品が見つかりません: $barcode'),
          backgroundColor: Colors.red,
        ),
      );
    }
    // Clear the text field for the next scan and re-focus
    _focusNode.requestFocus();
  }
  
  void _calculateTotals() {
    _totalItems = _scannedItems.fold(0, (sum, item) => sum + item.quantity);
    _totalAmount = _scannedItems.fold(0, (sum, item) => sum + (item.product.price * item.quantity));
  }

  void _incrementItem(int index) {
    setState(() {
      _scannedItems[index].quantity++;
      _calculateTotals();
    });
    _focusNode.requestFocus();
  }

  void _decrementItem(int index) {
    setState(() {
      if (_scannedItems[index].quantity > 1) {
        _scannedItems[index].quantity--;
      } else {
        _scannedItems.removeAt(index);
      }
      _calculateTotals();
    });
    _focusNode.requestFocus();
  }

  void _allClear() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const OperatorInputView()),
      (route) => false,
    );
  }

  Future<void> _subtotal() async {
    if (_scannedItems.isEmpty) return;

    // API送信用の明細データを作成
    final List<Map<String, dynamic>> details = _scannedItems.map((item) {
      return {
        'product_id': item.product.id,
        'product_name': item.product.name,
        'product_code': item.product.code,
        'quantity': item.quantity,
        'unit_price': item.product.price,
        'subtotal': item.product.price * item.quantity,
      };
    }).toList();

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentView(
          operatorName: widget.operatorName,
          totalAmount: _totalAmount,
          saleDetails: details,
        ),
      ),
    );

    _focusNode.requestFocus(); // 戻ってきたらフォーカスを戻す

    if (result == true) {
      setState(() {
        _scannedItems.clear();
        _calculateTotals();
      });
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_barcodeBuffer.isNotEmpty) {
          _onBarcodeScanned(_barcodeBuffer);
          _barcodeBuffer = '';
        }
        return KeyEventResult.handled;
      } else if (event.character != null) {
        _barcodeBuffer += event.character!;
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        appBar: AppBar(
          title: Text('担当: ${widget.operatorName}'),
        ),
        body: Row(
            children: [
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () => _focusNode.requestFocus(),
                  child: Container(
                    color: Colors.grey[200],
                    child: ListView.builder(
                      itemCount: _scannedItems.length,
                      itemBuilder: (context, index) {
                        final item = _scannedItems[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: ListTile(
                            title: Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('¥${item.product.price}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _decrementItem(index)),
                                Text('${item.quantity}', style: const TextStyle(fontSize: 18)),
                                IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _incrementItem(index)),
                                SizedBox(width: 100, child: Text('¥${item.product.price * item.quantity}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 16))),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              // Right side: Summary
              Expanded(
                flex: 1,
                child: GestureDetector(
                  onTap: () => _focusNode.requestFocus(),
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    color: Colors.blue[50],
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('点数', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        Text('$_totalItems', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        const Divider(height: 32),
                        const Text('合計', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        Text('¥ $_totalAmount', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.red), textAlign: TextAlign.center),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        floatingActionButton: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 32.0),
              child: SizedBox(
                height: 60,
                child: FloatingActionButton.extended(
                  heroTag: 'allClearBtn',
                  onPressed: _allClear,
                  label: const Text('オールクリア', style: TextStyle(fontSize: 18)),
                  icon: const Icon(Icons.delete_sweep, size: 28),
                  backgroundColor: Colors.orange,
                ),
              ),
            ),
            SizedBox(
              height: 80,
              width: 220,
              child: FloatingActionButton.extended(
                heroTag: 'subtotalBtn',
                onPressed: _subtotal,
                label: const Text('小計', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                icon: const Icon(Icons.payment, size: 40),
                backgroundColor: Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
