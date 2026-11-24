// 一覧選択方式の売上登録画面（バーコードスキャンではなく、商品/セット一覧から
// タップして数量を増減させるUI）。商品タブとセット商品タブを切り替えて操作する。
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onlipos/login/operator_input_view.dart';
import 'package:onlipos/product/catalog_service.dart';
import 'package:onlipos/product/product.dart';
import 'package:onlipos/product/product_image.dart';
import 'package:onlipos/product/product_repository.dart';
import 'package:onlipos/sale/cart_pricing.dart';
import 'package:onlipos/sale/option_select_dialog.dart';
import 'package:onlipos/sale/payment_view.dart';
import 'package:onlipos/sale/weight_input_dialog.dart';
import 'package:onlipos/sale/sale_item.dart';
import 'package:onlipos/sale/price_edit_dialog.dart';
import 'package:onlipos/sale/transfer_order_api.dart';

// ─── ウィジェット ─────────────────────────────────────────────────

class SaleListView extends StatefulWidget {
  final String operatorName;
  final int operatorId;

  const SaleListView({
    super.key,
    required this.operatorName,
    required this.operatorId,
  });

  @override
  State<SaleListView> createState() => _SaleListViewState();
}

class _SaleListViewState extends State<SaleListView>
    with SingleTickerProviderStateMixin {
  final ProductRepository _repo = ProductRepository();
  final TextEditingController _searchController = TextEditingController();

  List<ScannedItem> _allProductItems = [];
  List<ScannedItem> _filteredProductItems = [];
  List<ScannedItem> _allBundleItems = [];
  List<ScannedItem> _filteredBundleItems = [];

  bool _isLoading = true;
  late TabController _tabController;
  String _posRole = 'standard';

  bool get _isClient => _posRole == 'client';

  // 自動値引き・税の端数処理の設定
  CartPricing _pricing = const CartPricing();
  static const bool _eatIn = false;

  // 数量が1以上の行（これがそのままカートになる）
  List<ScannedItem> get _cart => [
    ..._allProductItems,
    ..._allBundleItems,
  ].where((i) => i.quantity > 0).toList();

  CartQuote get _quote => _pricing.quote(_cart);
  int get _totalItems => _quote.itemCount;
  int get _totalAmount => _quote.total;
  int get _totalTax => _quote.tax;

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

  // 商品・セット一覧をローカルDBから読み込み、セット商品は事前に価格・税額を計算する
  Future<void> _loadData() async {
    final products = await _repo.getAllProducts();
    final bundles = await _repo.getAllBundles();

    final pricing = await CatalogService.instance.cartPricing();
    final List<ScannedItem> bundleItems = [];
    for (final b in bundles) {
      final item = await _repo.bundleItem(b, quantity: 0);
      if (item != null) bundleItems.add(item);
    }

    if (!mounted) return;
    setState(() {
      _pricing = pricing;
      _allProductItems = products
          .map((p) => ScannedItem(product: p, quantity: 0, eatIn: _eatIn))
          .toList();
      // タイムセールの価格を一覧に反映する
      _pricing.quote(_allProductItems);
      _allBundleItems = bundleItems;
      _isLoading = false;
      _applyFilter();
    });
  }

  // 検索文字列（商品名・コード）で表示リストを絞り込む
  void _applyFilter() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredProductItems = _groupVariants(_allProductItems);
        _filteredBundleItems = List.of(_allBundleItems);
      } else {
        _filteredProductItems = _groupVariants(
          _allProductItems.where(
            (i) =>
                i.product.name.toLowerCase().contains(q) ||
                i.product.code.toLowerCase().contains(q),
          ),
        );
        _filteredBundleItems = _allBundleItems
            .where(
              (i) =>
                  i.product.name.toLowerCase().contains(q) ||
                  i.product.code.toLowerCase().contains(q),
            )
            .toList();
      }
    });
  }

  Future<void> _incrementProduct(int indexInFiltered) async {
    var item = _filteredProductItems[indexInFiltered];
    // バリエーション（色・サイズなど）のある商品は、選んでから登録する
    if (!_isExtraRow(item) && item.product.variantGroup != null) {
      final chosen = await _chooseVariant(item.product);
      if (chosen == null || !mounted) return;
      item = chosen;
    }
    // 量り売り・オプションのある商品は、入力内容ごとに別の行として加える
    if (item.weightGrams == null && item.product.soldByWeight) {
      final grams = await showDialog<int>(
        context: context,
        builder: (_) => WeightInputDialog(product: item.product),
      );
      if (grams == null) return;
      return _insertRow(
        ScannedItem(product: item.product, weightGrams: grams, eatIn: _eatIn),
      );
    }
    if (item.options.isEmpty && item.product.optionGroups.isNotEmpty) {
      final options = await showOptionSelectDialog(context, item.product);
      if (options == null) return;
      if (options.isNotEmpty) {
        return _insertRow(
          ScannedItem(product: item.product, options: options, eatIn: _eatIn),
        );
      }
    }
    if (!mounted) return;
    setState(() => item.quantity++);
  }

  Future<ScannedItem?> _chooseVariant(Product product) {
    final variants = _allProductItems
        .where(
          (i) =>
              !_isExtraRow(i) && i.product.variantGroup == product.variantGroup,
        )
        .toList();
    if (variants.length == 1) return Future.value(variants.first);
    return showDialog<ScannedItem>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(product.variantGroup!),
        children: [
          for (final v in variants)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, v),
              child: Text(
                '${v.product.variantName ?? v.product.name}  ¥${v.price}',
              ),
            ),
        ],
      ),
    );
  }

  // 同じバリエーショングループは1行にまとめる（数量のある行はすべて表示する）
  List<ScannedItem> _groupVariants(Iterable<ScannedItem> items) {
    final shown = <String>{};
    return items.where((i) {
      final group = i.product.variantGroup;
      if (group == null || i.quantity > 0 || _isExtraRow(i)) return true;
      return shown.add(group);
    }).toList();
  }

  void _insertRow(ScannedItem item) {
    if (!mounted) return;
    _allProductItems.insert(0, item);
    _applyFilter();
  }

  // 追加で作った行（価格変更・量り売り・オプション）か
  bool _isExtraRow(ScannedItem item) =>
      item.overridePrice != null ||
      item.weightGrams != null ||
      item.options.isNotEmpty;

  void _clearCart() {
    setState(() {
      _allProductItems.removeWhere(_isExtraRow);
      for (final item in [..._allProductItems, ..._allBundleItems]) {
        item.quantity = 0;
      }
    });
    _applyFilter();
  }

  void _decrementProduct(int indexInFiltered) {
    final item = _filteredProductItems[indexInFiltered];
    if (item.quantity <= 0) return;
    item.quantity--;
    // カスタム価格アイテムは0になったらリストから削除する
    if (item.quantity == 0 && _isExtraRow(item)) {
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

  // 価格変更ダイアログで選んだ価格の商品を追加する（元価格と同額なら通常行に統合）
  Future<void> _addCustomPriceItem(Product product) async {
    final result = await showDialog<({int price, String? reason})>(
      context: context,
      builder: (ctx) => PriceEditDialog(product: product),
    );

    if (result == null) return;
    final newPrice = result.price;
    final reason = result.reason;

    if (newPrice == product.price) {
      // 元の価格と同じなら通常の行のカウンタを上げる
      final regularIdx = _allProductItems.indexWhere(
        (i) => i.product.id == product.id && i.overridePrice == null,
      );
      if (regularIdx != -1) {
        setState(() => _allProductItems[regularIdx].quantity++);
      }
      return;
    }

    // 同じ商品・同じ価格のカスタムアイテムが既にあればそのカウンタを上げる
    final existingIdx = _allProductItems.indexWhere(
      (i) => i.product.id == product.id && i.overridePrice == newPrice,
    );
    if (existingIdx != -1) {
      setState(() => _allProductItems[existingIdx].quantity++);
    } else {
      // 新規カスタムアイテムを先頭に挿入し、フィルタ済みリストを再構築
      _allProductItems.insert(
        0,
        ScannedItem(
          product: product,
          overridePrice: newPrice,
          discountReason: reason,
          eatIn: _eatIn,
          quantity: 1,
        ),
      );
      _applyFilter();
    }
  }

  void _allClear() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const OperatorInputView(isListView: true),
      ),
      (route) => false,
    );
  }

  // 選択中の商品・セットから明細を組み立て、決済画面へ遷移する
  Future<void> _subtotal() async {
    final cart = _cart;
    if (cart.isEmpty) return;

    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentView(
          operatorName: widget.operatorName,
          operatorId: widget.operatorId,
          items: cart,
          pricing: _pricing,
        ),
      ),
    );

    if (result == true) _clearCart();
    // 商品マスタが更新されたら、新しい価格で選び直してもらう
    if (result == 'master_updated') await _loadData();
  }

  // ─── クライアントモード：ホストへ転送 ────────────────────────
  Future<void> _transferToHost() async {
    final items = _cart;

    if (items.isEmpty) {
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

    final capturedTotal = _totalAmount;

    try {
      final transferId = await TransferOrderApi.createTransfer(
        operatorName: widget.operatorName,
        operatorId: widget.operatorId,
        totalAmount: capturedTotal,
        items: items,
      );
      _clearCart();
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
          SnackBar(content: Text('転送に失敗しました: $e'), backgroundColor: Colors.red),
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
          const Text(
            '点数',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          Text(
            '$_totalItems',
            style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const Divider(height: 32),
          const Text(
            '合計（税込）',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          Text(
            '¥ $_totalAmount',
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
            textAlign: TextAlign.center,
          ),
          if (_totalTax > 0) ...[
            const SizedBox(height: 8),
            Text(
              'うち消費税 ¥$_totalTax',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
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
            leading: item.product.imageVersion == null
                ? null
                : ProductImage(product: item.product),
            title: Text(
              item.product.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
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
                      Text(
                        '(税${item.product.taxRate}%)',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  )
                : Text(
                    '${item.product.code}  ¥${item.product.price}  (税${item.product.taxRate}%)',
                  ),
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
                  unitPrice: item.quantity == 0 ? item.price : null,
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
              child: Text(
                'セット',
                style: TextStyle(fontSize: 12, color: Colors.orange[900]),
              ),
            ),
            title: Text(
              item.product.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${item.product.code}  ${item.components.length}点セット',
            ),
            trailing: _quantityControl(
              quantity: item.quantity,
              unitPrice: item.price,
              subtotal: item.quantity > 0 ? item.subtotal : null,
              onDecrement: () => _decrementBundle(index),
              onIncrement: () => _incrementBundle(index),
            ),
          ),
        );
      },
    );
  }

  // 数量の増減ボタンと金額表示をまとめた共通ウィジェット
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
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: onDecrement,
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: onIncrement,
        ),
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
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
                    children: [_buildProductTab(), _buildBundleTab()],
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
                        label: const Text(
                          '転　送',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _totalItems > 0
                              ? const Color(0xFF2D89EF)
                              : Colors.grey,
                          foregroundColor: Colors.white,
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: _totalItems > 0 ? _subtotal : null,
                        icon: const Icon(Icons.payment, size: 28),
                        label: const Text(
                          '小計',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _totalItems > 0
                              ? Colors.green
                              : Colors.grey,
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
