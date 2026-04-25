import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onlipos/login/operator_input_view.dart';
import 'package:onlipos/product/product.dart';
import 'package:onlipos/product/product_repository.dart';
import 'package:onlipos/sale/payment_view.dart';
import 'package:onlipos/sale/sale_item.dart';
import 'package:onlipos/sale/table_order_store.dart';
import 'package:onlipos/sale/hold_order_store.dart';
import 'package:onlipos/sale/table_order_api.dart';
import 'package:onlipos/sale/hold_order_api.dart';
import 'package:onlipos/sale/transfer_order_api.dart';
import 'package:onlipos/product/product_lookup_api.dart';
import 'package:onlipos/sale/escpos/lan_recipt_api.dart';

export 'sale_item.dart' show ScannedItem;

class SaleScanView extends StatefulWidget {
  final String operatorName;
  final int operatorId;
  /// 'standard' | 'restaurant' | 'retail'
  final String storeMode;
  /// 飲食店モード時の卓番（restaurant モードのみ使用）
  final String? tableNumber;
  /// ホストがクライアントから受け取った転送注文のプリロードアイテム
  final List<ScannedItem>? initialItems;

  const SaleScanView({
    super.key,
    required this.operatorName,
    required this.operatorId,
    this.storeMode = 'standard',
    this.tableNumber,
    this.initialItems,
  });

  @override
  State<SaleScanView> createState() => _SaleScanViewState();
}

class _SaleScanViewState extends State<SaleScanView> {
  final FocusNode _focusNode = FocusNode();
  final ProductRepository _productRepository = ProductRepository();
  final List<ScannedItem> _scannedItems = [];
  int _totalItems = 0;
  int _totalAmount = 0;
  int _totalTax = 0;
  String _barcodeBuffer = '';
  bool _isLoadingTable = false;
  String _posRole = 'standard'; // 'standard' | 'host' | 'client'

  bool get _isRestaurant => widget.storeMode == 'restaurant';
  bool get _isRetail => widget.storeMode == 'retail';
  bool get _isClient => _posRole == 'client';

  @override
  void initState() {
    super.initState();
    _loadPosRole();
    // プリロードアイテムがあれば展開（ホスト受け取り時）
    if (widget.initialItems != null && widget.initialItems!.isNotEmpty) {
      _scannedItems.addAll(widget.initialItems!);
      _calculateTotals();
    }
    if (_isRestaurant && widget.tableNumber != null) {
      _loadTableOrder();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).requestFocus(_focusNode);
      });
    }
  }

  Future<void> _loadPosRole() async {
    const storage = FlutterSecureStorage();
    final role = await storage.read(key: 'PosRole') ?? 'standard';
    if (mounted) setState(() => _posRole = role);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  // ---- テーブル注文の読み込み（飲食店モード） ----------------------

  Future<void> _loadTableOrder() async {
    setState(() => _isLoadingTable = true);
    List<ScannedItem> items = [];
    try {
      items = await TableOrderApi.getItems(widget.tableNumber!);
    } catch (_) {
      // サーバー障害時はローカルフォールバック
      items = TableOrderStore().getItems(widget.tableNumber!);
    }
    if (!mounted) return;
    setState(() {
      _isLoadingTable = false;
      if (items.isNotEmpty) {
        _scannedItems.addAll(items);
        _calculateTotals();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).requestFocus(_focusNode);
    });
  }

  /// テーブル注文をサーバーに非同期保存（fire-and-forget）。
  /// 失敗時はローカルストアにフォールバック。
  void _triggerTableSave() {
    if (!_isRestaurant || widget.tableNumber == null) return;
    final snapshot = List<ScannedItem>.from(_scannedItems);
    TableOrderApi.saveItems(widget.tableNumber!, snapshot).catchError((_) {
      TableOrderStore().saveItems(widget.tableNumber!, snapshot);
    });
  }

  // ---- バーコードスキャン ------------------------------------------

  Future<void> _onBarcodeScanned(String barcode) async {
    if (barcode.isEmpty) return;

    final product = await _productRepository.findProductByCode(barcode);
    if (product != null) {
      setState(() {
        // overridePrice が設定されていない行のみ同一商品としてマージする
        final existingIdx = _scannedItems.indexWhere(
            (item) => item.product.code == barcode && item.bundleCode == null && item.overridePrice == null);
        if (existingIdx != -1) {
          _scannedItems[existingIdx].quantity++;
        } else {
          _scannedItems.insert(0, ScannedItem(product: product));
        }
        _calculateTotals();
      });
      _triggerTableSave();
      _focusNode.requestFocus();
      return;
    }

    final bundle = await _productRepository.findBundleByCode(barcode);
    if (bundle != null) {
      final expandedProducts = await _productRepository.expandBundle(bundle);
      if (expandedProducts.isEmpty) {
        _showNotFound(barcode);
        return;
      }
      setState(() {
        for (final product in expandedProducts) {
          final item = bundle.items.firstWhere(
              (i) => i.productId == product.id,
              orElse: () => BundleItem(productId: product.id, quantity: 1));
          final existingIdx = _scannedItems.indexWhere(
              (s) => s.product.id == product.id && s.bundleCode == bundle.code);
          if (existingIdx != -1) {
            _scannedItems[existingIdx].quantity += item.quantity;
          } else {
            _scannedItems.insert(
              0,
              ScannedItem(
                product: product,
                bundleCode: bundle.code,
                bundleName: bundle.name,
                quantity: item.quantity,
              ),
            );
          }
        }
        _calculateTotals();
      });
      _triggerTableSave();
      _focusNode.requestFocus();
      return;
    }

    // ローカルに存在しない場合はサーバ問い合わせを提案
    await _askAndLookupFromServer(barcode);
  }

  void _showNotFound(String barcode) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('商品が見つかりません: $barcode'),
        backgroundColor: Colors.red,
      ),
    );
    _focusNode.requestFocus();
  }

  Future<void> _askAndLookupFromServer(String barcode) async {
    final shouldQuery = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('商品が見つかりません'),
        content: Text('「$barcode」はローカルに登録がありません。\nサーバに問い合わせますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('NO'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('YES'),
          ),
        ],
      ),
    );

    if (shouldQuery != true || !mounted) {
      _focusNode.requestFocus();
      return;
    }

    try {
      final product = await ProductLookupApi.lookupByCode(barcode);
      if (!mounted) return;
      if (product == null) {
        _showNotFound(barcode);
        return;
      }
      setState(() {
        final existingIdx = _scannedItems.indexWhere(
            (item) => item.product.code == barcode && item.bundleCode == null && item.overridePrice == null);
        if (existingIdx != -1) {
          _scannedItems[existingIdx].quantity++;
        } else {
          _scannedItems.insert(0, ScannedItem(product: product));
        }
        _calculateTotals();
      });
      _triggerTableSave();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('サーバへの問い合わせに失敗しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
    _focusNode.requestFocus();
  }

  void _calculateTotals() {
    _totalItems = _scannedItems.fold(0, (sum, item) => sum + item.quantity);
    _totalAmount = _scannedItems.fold(0, (sum, item) => sum + item.subtotal);
    _totalTax = _scannedItems.fold(0, (sum, item) => sum + item.taxAmount);
  }

  Future<void> _editItemPrice(int index) async {
    final item = _scannedItems[index];
    final controller = TextEditingController(text: '${item.price}');
    final newPrice = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('価格変更'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('元の価格: ¥${item.product.price}'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '新しい価格',
                prefixText: '¥',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              onSubmitted: (_) {
                final p = int.tryParse(controller.text);
                if (p != null && p >= 0) Navigator.of(ctx).pop(p);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
          if (item.overridePrice != null)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(item.product.price),
              child: const Text('元の価格に戻す'),
            ),
          ElevatedButton(
            onPressed: () {
              final p = int.tryParse(controller.text);
              if (p != null && p >= 0) Navigator.of(ctx).pop(p);
            },
            child: const Text('変更'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (newPrice == null || !mounted) {
      _focusNode.requestFocus();
      return;
    }
    setState(() {
      final newOverride = newPrice == item.product.price ? null : newPrice;
      _scannedItems[index] = ScannedItem(
        product: item.product,
        bundleCode: item.bundleCode,
        bundleName: item.bundleName,
        quantity: item.quantity,
        overridePrice: newOverride,
      );
      _calculateTotals();
    });
    _triggerTableSave();
    _focusNode.requestFocus();
  }

  void _incrementItem(int index) {
    setState(() {
      _scannedItems[index].quantity++;
      _calculateTotals();
    });
    _triggerTableSave();
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
    _triggerTableSave();
    _focusNode.requestFocus();
  }

  void _allClear() {
    if (_isRestaurant && widget.tableNumber != null) {
      TableOrderApi.clearTable(widget.tableNumber!).catchError((_) {
        TableOrderStore().clearTable(widget.tableNumber!);
      });
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const OperatorInputView()),
      (route) => false,
    );
  }

  Future<void> _subtotal() async {
    if (_scannedItems.isEmpty) return;

    final List<Map<String, dynamic>> details = _scannedItems.map((item) {
      final taxRate = item.product.taxRate;
      final sub = item.subtotal;
      final exTax = (sub * 100 / (100 + taxRate)).floor();
      final taxAmt = sub - exTax;
      return {
        'product_id': item.product.id,
        'product_name': item.product.name,
        'product_code': item.product.code,
        'quantity': item.quantity,
        'unit_price': item.price,
        'subtotal': sub,
        'tax_rate': taxRate,
        'tax_amount': taxAmt,
        if (item.bundleCode != null) 'bundle_code': item.bundleCode,
      };
    }).toList();

    final int totalExTax = _totalAmount - _totalTax;

    final String? extraInfo = _isRestaurant && widget.tableNumber != null
        ? '卓 ${widget.tableNumber}'
        : null;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentView(
          operatorName: widget.operatorName,
          operatorId: widget.operatorId,
          totalAmount: _totalAmount,
          subtotalExTax: totalExTax,
          taxAmount: _totalTax,
          saleDetails: details,
          extraInfo: extraInfo,
        ),
      ),
    );

    _focusNode.requestFocus();

    if (result == true) {
      if (_isRestaurant && widget.tableNumber != null) {
        TableOrderApi.clearTable(widget.tableNumber!).catchError((_) {
          TableOrderStore().clearTable(widget.tableNumber!);
        });
      }
      setState(() {
        _scannedItems.clear();
        _calculateTotals();
      });
    }
  }

  // ---- 小売店モード：保留 ----------------------------------------

  void _holdOrRecall() {
    if (_scannedItems.isEmpty) {
      _showHoldRecallDialog();
    } else {
      _holdCurrentOrder();
    }
  }

  Future<void> _holdCurrentOrder() async {
    final details = _scannedItems.map((item) {
      return {
        'product_name': item.product.name,
        'product_code': item.product.code,
        'quantity': item.quantity,
        'unit_price': item.price,
        'subtotal': item.subtotal,
      };
    }).toList();

    int holdNumber;
    try {
      holdNumber = await HoldOrderApi.createHold(
        operatorName: widget.operatorName,
        operatorId: widget.operatorId,
        totalAmount: _totalAmount,
        items: _scannedItems,
      );
    } catch (_) {
      // フォールバック：ローカルストア
      holdNumber = HoldOrderStore().addHold(
        operatorName: widget.operatorName,
        operatorId: widget.operatorId,
        items: _scannedItems,
        totalAmount: _totalAmount,
      );
    }

    try {
      await ReceiptPrinter.printHoldSlip(
        holdNumber: holdNumber,
        operatorName: widget.operatorName,
        totalAmount: _totalAmount,
        details: details,
      );
    } catch (_) {
      // 印刷失敗は無視
    }

    setState(() {
      _scannedItems.clear();
      _calculateTotals();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保留番号 $holdNumber で保留しました'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    _focusNode.requestFocus();
  }

  void _showHoldRecallDialog() {
    showDialog(
      context: context,
      builder: (context) => _HoldRecallDialog(
        onConfirmed: (holdNumber) async {
          RecalledHoldOrder? recalled;
          try {
            recalled = await HoldOrderApi.recallHold(holdNumber);
          } catch (_) {
            // フォールバック：ローカルストア
            final localHold = HoldOrderStore().recallHoldWithInfo(holdNumber);
            if (localHold != null) {
              recalled = RecalledHoldOrder(
                holdNumber: localHold.holdNumber,
                operatorName: localHold.operatorName,
                operatorId: localHold.operatorId,
                totalAmount: localHold.totalAmount,
                items: localHold.items.map((e) => e.copy()).toList(),
              );
            }
          }
          if (recalled == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('保留番号 $holdNumber が見つかりません'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
          setState(() {
            _scannedItems.clear();
            _scannedItems.addAll(recalled!.items);
            _calculateTotals();
          });
          _focusNode.requestFocus();
        },
      ),
    );
  }

  // ---- クライアントモード：ホストへ転送 ----------------------------

  Future<void> _transferToHost() async {
    if (_scannedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('転送する商品がありません'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ホストに転送しますか？'),
        content: Text(
          '${_scannedItems.length}種類  $_totalItems点\n¥$_totalAmount\n\n'
          'ホストのレジに転送し、このカートをクリアします。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2D89EF),
              foregroundColor: Colors.white,
            ),
            child: const Text('転送する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final transferId = await TransferOrderApi.createTransfer(
        operatorName: widget.operatorName,
        operatorId:   widget.operatorId,
        totalAmount:  _totalAmount,
        items:        _scannedItems,
        tableNumber:  widget.tableNumber,
      );

      setState(() {
        _scannedItems.clear();
        _calculateTotals();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('転送しました（転送ID: $transferId）'),
            backgroundColor: const Color(0xFF2D89EF),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('転送に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    _focusNode.requestFocus();
  }

  // ---- キーボードスキャン -------------------------------------------

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

  // ---- UI ----------------------------------------------------------

  String get _appBarTitle {
    if (_isRestaurant && widget.tableNumber != null) {
      return '卓 ${widget.tableNumber}  担当: ${widget.operatorName}';
    }
    return '担当: ${widget.operatorName}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingTable) {
      return Scaffold(
        appBar: AppBar(title: Text(_appBarTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_appBarTitle),
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
                      final hasOverride = item.overridePrice != null;
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: InkWell(
                          onLongPress: () => _editItemPrice(index),
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            title: Row(
                              children: [
                                if (item.bundleCode != null)
                                  Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange[100],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('セット',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange[900])),
                                  ),
                                Expanded(
                                  child: Text(item.product.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            subtitle: hasOverride
                                ? Row(
                                    children: [
                                      Text(
                                        '¥${item.product.price}',
                                        style: TextStyle(
                                          decoration: TextDecoration.lineThrough,
                                          color: Colors.grey[500],
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.red[50],
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.red.shade200),
                                        ),
                                        child: Text(
                                          '¥${item.overridePrice}',
                                          style: TextStyle(
                                            color: Colors.red[700],
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text('(税${item.product.taxRate}%)',
                                          style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                                    ],
                                  )
                                : Text('¥${item.product.price}  (税${item.product.taxRate}%)'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                    icon: const Icon(
                                        Icons.remove_circle_outline),
                                    onPressed: () => _decrementItem(index)),
                                Text('${item.quantity}',
                                    style: const TextStyle(fontSize: 18)),
                                IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: () => _incrementItem(index)),
                                GestureDetector(
                                  onTap: () => _editItemPrice(index),
                                  child: SizedBox(
                                    width: 100,
                                    child: Text(
                                      '¥${item.subtotal}',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: hasOverride ? Colors.red[700] : null,
                                        fontWeight: hasOverride ? FontWeight.bold : null,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
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
                      const Text('点数',
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                      Text('$_totalItems',
                          style: const TextStyle(
                              fontSize: 48, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                      const Divider(height: 32),
                      const Text('合計（税込）',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                      Text('¥ $_totalAmount',
                          style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: Colors.red),
                          textAlign: TextAlign.center),
                      if (_totalTax > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          'うち消費税 ¥$_totalTax',
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(
              children: [
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _allClear,
                    icon: const Icon(Icons.delete_sweep),
                    label: const Text('オールクリア', style: TextStyle(fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                if (_isRetail && !_isClient) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _holdOrRecall,
                      icon: Icon(
                        _scannedItems.isEmpty
                            ? Icons.call_received
                            : Icons.pause_circle_outline,
                      ),
                      label: Text(
                        _scannedItems.isEmpty ? '保留呼び出し' : '保　留',
                        style: const TextStyle(fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                SizedBox(
                  height: 60,
                  width: 180,
                  child: _isClient
                      ? ElevatedButton.icon(
                          onPressed: _transferToHost,
                          icon: const Icon(Icons.send, size: 28),
                          label: const Text('転　送',
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2D89EF),
                            foregroundColor: Colors.white,
                          ),
                        )
                      : ElevatedButton.icon(
                          onPressed: _subtotal,
                          icon: const Icon(Icons.payment, size: 28),
                          label: const Text('小計',
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- 保留呼び出しダイアログ -----------------------------------------

class _HoldRecallDialog extends StatefulWidget {
  final void Function(int holdNumber) onConfirmed;

  const _HoldRecallDialog({required this.onConfirmed});

  @override
  State<_HoldRecallDialog> createState() => _HoldRecallDialogState();
}

class _HoldRecallDialogState extends State<_HoldRecallDialog> {
  final TextEditingController _controller = TextEditingController();
  List<HoldOrderEntry> _holds = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHolds();
  }

  Future<void> _loadHolds() async {
    List<HoldOrderEntry> holds = [];
    try {
      holds = await HoldOrderApi.getAllHolds();
    } catch (_) {
      // フォールバック：ローカルストアから変換
      holds = HoldOrderStore().allHolds.map((h) {
        return HoldOrderEntry(
          holdNumber: h.holdNumber,
          operatorName: h.operatorName,
          operatorId: h.operatorId,
          totalAmount: h.totalAmount,
          createdAt: h.createdAt,
        );
      }).toList();
    }
    if (mounted) {
      setState(() {
        _holds = holds;
        _isLoading = false;
      });
    }
  }

  void _confirm() {
    final num = int.tryParse(_controller.text.trim());
    if (num == null) return;
    widget.onConfirmed(num);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('保留呼び出し'),
      content: SizedBox(
        width: 420,
        child: _isLoading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_holds.isNotEmpty) ...[
                      const Text('保留中の注文',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey)),
                      const SizedBox(height: 8),
                      ..._holds.map(
                        (hold) => Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.purple[100],
                              child: Text(
                                '${hold.holdNumber}',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple[900]),
                              ),
                            ),
                            title: Text('担当: ${hold.operatorName}'),
                            subtitle: Text(
                                '¥${hold.totalAmount}  ${hold.createdAt.toLocal().toString().substring(11, 16)}'),
                            onTap: () {
                              widget.onConfirmed(hold.holdNumber);
                              Navigator.of(context).pop();
                            },
                          ),
                        ),
                      ),
                      const Divider(height: 24),
                    ],
                    TextField(
                      controller: _controller,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      autofocus: _holds.isEmpty,
                      decoration: const InputDecoration(
                        labelText: '保留番号を入力',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontSize: 24),
                      onSubmitted: (_) => _confirm(),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル')),
        ElevatedButton(onPressed: _confirm, child: const Text('呼び出し')),
      ],
    );
  }
}
