import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onlipos/login/operator_input_view.dart';
import 'package:onlipos/product/product.dart';
import 'package:onlipos/product/product_repository.dart';
import 'package:onlipos/sale/payment_view.dart';
import 'package:onlipos/sale/sale_item.dart';
import 'package:onlipos/sale/transfer_order_api.dart';

// ─── データモデル ─────────────────────────────────────────────────

class _ProductItem {
  final Product product;
  // null の場合は product.price を使用。値引き・賞味期限値変更などで上書きする
  final int? overridePrice;
  int quantity;

  _ProductItem({required this.product, this.overridePrice, this.quantity = 0});

  int get effectivePrice => overridePrice ?? product.price;
  int get subtotal => effectivePrice * quantity;
  int get taxAmount {
    final taxRate = product.taxRate;
    final exTax = (subtotal * 100 / (100 + taxRate)).floor();
    return subtotal - exTax;
  }
}

class _BundleItem {
  final ProductBundle bundle;
  int quantity;
  /// 1セット分の実際の合計価格（bundle.price > 0 ならそれ、0なら構成商品合計）
  final int pricePerUnit;
  /// 1セット分の消費税額
  final int taxPerUnit;

  _BundleItem({
    required this.bundle,
    this.quantity = 0,
    this.pricePerUnit = 0,
    this.taxPerUnit = 0,
  });

  int get subtotal => pricePerUnit * quantity;
  int get taxAmount => taxPerUnit * quantity;
}

// ─── ウィジェット ─────────────────────────────────────────────────

class SaleListView extends StatefulWidget {
  final String operatorName;
  final int operatorId;

  const SaleListView({super.key, required this.operatorName, required this.operatorId});

  @override
  State<SaleListView> createState() => _SaleListViewState();
}

class _SaleListViewState extends State<SaleListView>
    with SingleTickerProviderStateMixin {
  final ProductRepository _repo = ProductRepository();
  final TextEditingController _searchController = TextEditingController();

  List<_ProductItem> _allProductItems = [];
  List<_ProductItem> _filteredProductItems = [];
  List<_BundleItem> _allBundleItems = [];
  List<_BundleItem> _filteredBundleItems = [];

  bool _isLoading = true;
  late TabController _tabController;
  String _posRole = 'standard';

  bool get _isClient => _posRole == 'client';

  int get _totalItems =>
      _allProductItems.fold(0, (s, i) => s + i.quantity) +
      _allBundleItems.fold(0, (s, i) => s + i.quantity);

  int get _totalAmount =>
      _allProductItems.fold(0, (s, i) => s + i.subtotal) +
      _allBundleItems.fold(0, (s, i) => s + i.subtotal);

  int get _totalTax =>
      _allProductItems.fold(0, (s, i) => s + i.taxAmount) +
      _allBundleItems.fold(0, (s, i) => s + i.taxAmount);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(_applyFilter);
    _loadPosRole();
    _loadData();
  }

  Future<void> _loadPosRole() async {
    const storage = FlutterSecureStorage();
    final role = await storage.read(key: 'PosRole') ?? 'standard';
    if (mounted) setState(() => _posRole = role);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final products = await _repo.getAllProducts();
    final bundles = await _repo.getAllBundles();

    // バンドルごとに構成商品を展開し、税額と合計価格を事前計算する
    final List<_BundleItem> bundleItems = [];
    for (final b in bundles) {
      int taxPerUnit = 0;
      int componentTotal = 0;
      final expandedProducts = await _repo.expandBundle(b);
      for (final ep in expandedProducts) {
        final bItem = b.items.firstWhere(
          (i) => i.productId == ep.id,
          orElse: () => BundleItem(productId: ep.id, quantity: 1),
        );
        final qty = bItem.quantity;
        final sub = ep.price * qty;
        final exTax = (sub * 100 / (100 + ep.taxRate)).floor();
        taxPerUnit += sub - exTax;
        componentTotal += sub;
      }
      final pricePerUnit = b.price > 0 ? b.price : componentTotal;
      bundleItems.add(_BundleItem(
        bundle: b,
        pricePerUnit: pricePerUnit,
        taxPerUnit: taxPerUnit,
      ));
    }

    if (!mounted) return;
    setState(() {
      _allProductItems = products.map((p) => _ProductItem(product: p)).toList();
      _allBundleItems = bundleItems;
      _isLoading = false;
      _applyFilter();
    });
  }

  void _applyFilter() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredProductItems = List.of(_allProductItems);
        _filteredBundleItems = List.of(_allBundleItems);
      } else {
        _filteredProductItems = _allProductItems
            .where((i) =>
                i.product.name.toLowerCase().contains(q) ||
                i.product.code.toLowerCase().contains(q))
            .toList();
        _filteredBundleItems = _allBundleItems
            .where((i) =>
                i.bundle.name.toLowerCase().contains(q) ||
                i.bundle.code.toLowerCase().contains(q))
            .toList();
      }
    });
  }

  void _incrementProduct(int indexInFiltered) {
    setState(() {
      _filteredProductItems[indexInFiltered].quantity++;
    });
  }

  void _decrementProduct(int indexInFiltered) {
    final item = _filteredProductItems[indexInFiltered];
    if (item.quantity <= 0) return;
    item.quantity--;
    // カスタム価格アイテムは0になったらリストから削除する
    if (item.quantity == 0 && item.overridePrice != null) {
      _allProductItems.remove(item);
      _applyFilter();
    } else {
      setState(() {});
    }
  }

  void _incrementBundle(int indexInFiltered) {
    setState(() {
      _filteredBundleItems[indexInFiltered].quantity++;
    });
  }

  void _decrementBundle(int indexInFiltered) {
    setState(() {
      if (_filteredBundleItems[indexInFiltered].quantity > 0) {
        _filteredBundleItems[indexInFiltered].quantity--;
      }
    });
  }

  Future<void> _addCustomPriceItem(Product product) async {
    final controller = TextEditingController(text: '${product.price}');
    final newPrice = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('価格変更で追加'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('元の価格: ¥${product.price}'),
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
          ElevatedButton(
            onPressed: () {
              final p = int.tryParse(controller.text);
              if (p != null && p >= 0) Navigator.of(ctx).pop(p);
            },
            child: const Text('追加'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (newPrice == null) return;

    if (newPrice == product.price) {
      // 元の価格と同じなら通常の行のカウンタを上げる
      final regularIdx = _allProductItems.indexWhere(
          (i) => i.product.id == product.id && i.overridePrice == null);
      if (regularIdx != -1) {
        setState(() => _allProductItems[regularIdx].quantity++);
      }
      return;
    }

    // 同じ商品・同じ価格のカスタムアイテムが既にあればそのカウンタを上げる
    final existingIdx = _allProductItems.indexWhere(
        (i) => i.product.id == product.id && i.overridePrice == newPrice);
    if (existingIdx != -1) {
      setState(() => _allProductItems[existingIdx].quantity++);
    } else {
      // 新規カスタムアイテムを先頭に挿入し、フィルタ済みリストを再構築
      _allProductItems.insert(
        0,
        _ProductItem(product: product, overridePrice: newPrice, quantity: 1),
      );
      _applyFilter();
    }
  }

  void _allClear() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OperatorInputView(isListView: true)),
      (route) => false,
    );
  }

  Future<void> _subtotal() async {
    final selectedProducts = _allProductItems.where((i) => i.quantity > 0).toList();
    final selectedBundles = _allBundleItems.where((i) => i.quantity > 0).toList();

    if (selectedProducts.isEmpty && selectedBundles.isEmpty) return;

    // 商品明細の構築
    final List<Map<String, dynamic>> details = [];
    int totalAmount = 0;
    int totalTax = 0;

    for (final item in selectedProducts) {
      final taxRate = item.product.taxRate;
      final sub = item.subtotal;
      final exTax = (sub * 100 / (100 + taxRate)).floor();
      final taxAmt = sub - exTax;
      totalAmount += sub;
      totalTax += taxAmt;
      details.add({
        'product_id': item.product.id,
        'product_name': item.product.name,
        'product_code': item.product.code,
        'quantity': item.quantity,
        'unit_price': item.effectivePrice,
        'subtotal': sub,
        'tax_rate': taxRate,
        'tax_amount': taxAmt,
      });
    }

    // バンドル明細の展開：構成商品ごとに明細を作成し bundle_code を付与
    for (final bundleItem in selectedBundles) {
      final bundle = bundleItem.bundle;
      final expandedProducts = await _repo.expandBundle(bundle);
      for (final ep in expandedProducts) {
        final bItem = bundle.items.firstWhere(
          (i) => i.productId == ep.id,
          orElse: () => BundleItem(productId: ep.id, quantity: 1),
        );
        final qty = bItem.quantity * bundleItem.quantity;
        final taxRate = ep.taxRate;
        final sub = ep.price * qty;
        final exTax = (sub * 100 / (100 + taxRate)).floor();
        final taxAmt = sub - exTax;
        totalAmount += sub;
        totalTax += taxAmt;
        details.add({
          'product_id': ep.id,
          'product_name': ep.name,
          'product_code': ep.code,
          'quantity': qty,
          'unit_price': ep.price,
          'subtotal': sub,
          'tax_rate': taxRate,
          'tax_amount': taxAmt,
          'bundle_code': bundle.code,
        });
      }
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentView(
          operatorName: widget.operatorName,
          operatorId: widget.operatorId,
          totalAmount: totalAmount,
          subtotalExTax: totalAmount - totalTax,
          taxAmount: totalTax,
          saleDetails: details,
        ),
      ),
    );

    if (result == true) {
      setState(() {
        for (final item in _allProductItems) {
          item.quantity = 0;
        }
        for (final item in _allBundleItems) {
          item.quantity = 0;
        }
        _applyFilter();
      });
    }
  }

  // ─── クライアントモード：ホストへ転送 ────────────────────────
  Future<void> _transferToHost() async {
    final selectedProducts = _allProductItems.where((i) => i.quantity > 0).toList();
    final selectedBundles = _allBundleItems.where((i) => i.quantity > 0).toList();

    if (selectedProducts.isEmpty && selectedBundles.isEmpty) {
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
          '合計 $_totalItems点\n¥$_totalAmount\n\n'
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

    // _ProductItem / _BundleItem → ScannedItem に変換
    final List<ScannedItem> items = [];
    for (final item in selectedProducts) {
      items.add(ScannedItem(product: item.product, quantity: item.quantity, overridePrice: item.overridePrice));
    }
    for (final bundleItem in selectedBundles) {
      final expandedProducts = await _repo.expandBundle(bundleItem.bundle);
      for (final ep in expandedProducts) {
        final bItem = bundleItem.bundle.items.firstWhere(
          (i) => i.productId == ep.id,
          orElse: () => BundleItem(productId: ep.id, quantity: 1),
        );
        items.add(ScannedItem(
          product: ep,
          bundleCode: bundleItem.bundle.code,
          bundleName: bundleItem.bundle.name,
          quantity: bItem.quantity * bundleItem.quantity,
        ));
      }
    }

    final capturedTotal = _totalAmount;

    try {
      final transferId = await TransferOrderApi.createTransfer(
        operatorName: widget.operatorName,
        operatorId: widget.operatorId,
        totalAmount: capturedTotal,
        items: items,
      );
      setState(() {
        for (final item in _allProductItems) {
          item.quantity = 0;
        }
        for (final item in _allBundleItems) {
          item.quantity = 0;
        }
        _applyFilter();
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
  }

  // ─── 共通の右パネル（合計表示）────────────────────────────────
  Widget _buildSummaryPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.blue[50],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('点数', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          Text('$_totalItems', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const Divider(height: 32),
          const Text('合計（税込）', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          Text('¥ $_totalAmount',
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.red),
              textAlign: TextAlign.center),
          if (_totalTax > 0) ...[
            const SizedBox(height: 8),
            Text('うち消費税 ¥$_totalTax',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center),
          ],
          const Spacer(),
        ],
      ),
    );
  }

  // ─── 商品タブ ────────────────────────────────────────────────
  Widget _buildProductTab() {
    if (_filteredProductItems.isEmpty) {
      return const Center(child: Text('該当する商品はありません'));
    }
    return ListView.builder(
      itemCount: _filteredProductItems.length,
      itemBuilder: (context, index) {
        final item = _filteredProductItems[index];
        final hasOverride = item.overridePrice != null;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: hasOverride ? Colors.red[50] : null,
          child: ListTile(
            title: Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: hasOverride
                ? Row(
                    children: [
                      Text(item.product.code),
                      const SizedBox(width: 8),
                      Text(
                        '¥${item.product.price}',
                        style: TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '¥${item.overridePrice}',
                          style: TextStyle(
                            color: Colors.red[800],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('(税${item.product.taxRate}%)',
                          style: TextStyle(color: Colors.grey[600])),
                    ],
                  )
                : Text('${item.product.code}  ¥${item.product.price}  (税${item.product.taxRate}%)'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!hasOverride)
                  IconButton(
                    icon: Icon(Icons.sell, size: 20, color: Colors.orange[700]),
                    tooltip: '価格変更で追加',
                    onPressed: () => _addCustomPriceItem(item.product),
                  ),
                _quantityControl(
                  quantity: item.quantity,
                  subtotal: item.quantity > 0 ? item.subtotal : null,
                  unitPrice: item.quantity == 0 ? item.effectivePrice : null,
                  onDecrement: () => _decrementProduct(index),
                  onIncrement: () => _incrementProduct(index),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── セット商品タブ ──────────────────────────────────────────
  Widget _buildBundleTab() {
    if (_allBundleItems.isEmpty) {
      return const Center(child: Text('セット商品が登録されていません'));
    }
    if (_filteredBundleItems.isEmpty) {
      return const Center(child: Text('該当するセット商品はありません'));
    }
    return ListView.builder(
      itemCount: _filteredBundleItems.length,
      itemBuilder: (context, index) {
        final item = _filteredBundleItems[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('セット', style: TextStyle(fontSize: 12, color: Colors.orange[900])),
            ),
            title: Text(item.bundle.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              '${item.bundle.code}  '
              '${item.bundle.items.length}点セット'
              '${item.bundle.price > 0 ? "  ¥${item.bundle.price}" : ""}',
            ),
            trailing: _quantityControl(
              quantity: item.quantity,
              unitPrice: item.pricePerUnit,
              subtotal: item.quantity > 0 ? item.subtotal : null,
              onDecrement: () => _decrementBundle(index),
              onIncrement: () => _incrementBundle(index),
            ),
          ),
        );
      },
    );
  }

  Widget _quantityControl({
    required int quantity,
    int? unitPrice,
    int? subtotal,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
  }) {
    // 数量>0 なら小計、数量=0 なら単価（参考）を表示
    final displayAmount = quantity > 0 ? subtotal : unitPrice;
    final isReference = quantity == 0 && unitPrice != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: onDecrement),
        SizedBox(
          width: 36,
          child: Text('$quantity', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
        ),
        IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: onIncrement),
        if (displayAmount != null)
          SizedBox(
            width: 90,
            child: Text(
              '¥$displayAmount',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 16,
                color: isReference ? Colors.grey : null,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '戻る',
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const OperatorInputView(isListView: true),
                ),
              );
            }
          },
        ),
        title: Text('担当: ${widget.operatorName} - 売上登録(一覧)'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '商品名・コードで絞り込む',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _applyFilter();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                tabs: [
                  Tab(text: '商品 (${_filteredProductItems.length})'),
                  Tab(text: 'セット (${_filteredBundleItems.length})'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildProductTab(),
                      _buildBundleTab(),
                    ],
                  ),
                ),
                Expanded(flex: 1, child: _buildSummaryPanel()),
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
              const Spacer(),
              SizedBox(
                height: 60,
                width: 180,
                child: _isClient
                    ? ElevatedButton.icon(
                        onPressed: _totalItems > 0 ? _transferToHost : null,
                        icon: const Icon(Icons.send, size: 28),
                        label: const Text('転　送',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _totalItems > 0 ? const Color(0xFF2D89EF) : Colors.grey,
                          foregroundColor: Colors.white,
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: _totalItems > 0 ? _subtotal : null,
                        icon: const Icon(Icons.payment, size: 28),
                        label: const Text('小計',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _totalItems > 0 ? Colors.green : Colors.grey,
                          foregroundColor: Colors.white,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
