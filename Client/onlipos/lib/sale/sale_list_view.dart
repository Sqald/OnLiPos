// 一覧選択方式の売上登録画面（バーコードスキャンではなく、商品/セット一覧から
// タップして数量を増減させるUI）。商品タブとセット商品タブを切り替えて操作する。
import 'package:flutter/material.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:onlipos/sale/cart_panel.dart';
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
                '${v.product.variantName ?? v.product.name}　${yen(v.price)}',
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

  // 選んだ商品をすべて取り消す（担当者はそのまま続けて会計できる）
  Future<void> _allClear() async {
    if (_totalItems == 0) return;
    final ok = await confirm(
      context,
      title: '商品をすべて取り消しますか？',
      message: '選んだ$_totalItems点を取り消します。',
      okLabel: 'すべて取り消す',
      danger: true,
    );
    if (ok && mounted) _clearCart();
  }

  // 商品が残っているときは、消えることを確認してから画面を離れる
  Future<bool> _confirmLeave() async {
    if (_totalItems == 0) return true;
    return confirm(
      context,
      title: '会計をやめますか？',
      message: '選んだ$_totalItems点は取り消されます。',
      okLabel: '会計をやめる',
      cancelLabel: '会計を続ける',
      danger: true,
    );
  }

  Future<void> _leave() async {
    if (await _confirmLeave() && mounted) Navigator.of(context).pop();
  }

  Future<void> _changeOperator() async {
    if (!await _confirmLeave() || !mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const OperatorInputView(isListView: true),
      ),
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
      showMessage(context, '転送する商品がありません', MessageType.error);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ホスト機に送りますか？'),
        content: Text(
          '$_totalItems点　${yen(_totalAmount)}\n\n'
          'ホスト機のレジに送り、この画面の商品を空にします。',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('やめる'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2D89EF),
              foregroundColor: Colors.white,
            ),
            child: const Text('送る'),
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
        showMessage(context, '転送しました（転送ID: $transferId）', MessageType.success);
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, '転送に失敗しました: $e', MessageType.error);
      }
    }
  }

  // 商品の行（値段・税率・数量）
  Widget _buildRow({
    required ScannedItem item,
    Widget? leading,
    required String detail,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
    VoidCallback? onChangePrice,
  }) {
    final changed = item.overridePrice != null;
    final selected = item.quantity > 0;
    return Card(
      color: selected ? AppColors.primarySoft : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPlus,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Row(
            children: [
              if (leading != null) ...[leading, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.options.isEmpty
                          ? item.product.name
                          : '${item.product.name}（${item.options.map((o) => o.name).join('・')}）',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (changed)
                          Text(
                            yen(item.product.price),
                            style: const TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: AppColors.muted,
                            ),
                          ),
                        Text(
                          yen(item.price),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: changed ? AppColors.danger : null,
                          ),
                        ),
                        Text(
                          detail,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onChangePrice != null)
                IconButton(
                  icon: const Icon(Icons.sell_outlined),
                  tooltip: '値段を変えて登録',
                  onPressed: onChangePrice,
                ),
              QuantityStepper(
                quantity: item.quantity,
                onMinus: selected ? onMinus : null,
                onPlus: onPlus,
              ),
              SizedBox(
                width: 92,
                child: Text(
                  selected ? yen(item.subtotal) : '',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductTab() {
    if (_filteredProductItems.isEmpty) return _noResult('商品');
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _filteredProductItems.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _filteredProductItems[index];
        return _buildRow(
          item: item,
          leading: item.product.imageVersion == null
              ? null
              : ProductImage(product: item.product),
          detail: '税${item.product.taxRate}%　${item.product.code}',
          onChangePrice: item.overridePrice != null
              ? null
              : () => _addCustomPriceItem(item.product),
          onMinus: () => _decrementProduct(index),
          onPlus: () => _incrementProduct(index),
        );
      },
    );
  }

  Widget _buildBundleTab() {
    if (_filteredBundleItems.isEmpty) return _noResult('セット商品');
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _filteredBundleItems.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _filteredBundleItems[index];
        return _buildRow(
          item: item,
          leading: const StatusBadge('セット', type: MessageType.warning),
          detail: '${item.components.length}点セット　${item.product.code}',
          onMinus: () => _decrementBundle(index),
          onPlus: () => _incrementBundle(index),
        );
      },
    );
  }

  Widget _noResult(String kind) {
    final searching = _searchController.text.trim().isNotEmpty;
    return EmptyState(
      icon: searching ? Icons.search_off : Icons.inventory_2_outlined,
      title: searching ? '見つかりませんでした' : '$kindが登録されていません',
      message: searching
          ? '別の言葉で探してみてください'
          : '管理画面で登録してから、「設定」の「商品データを更新」を押してください',
      action: searching
          ? OutlinedButton(
              onPressed: _searchController.clear,
              child: const Text('すべて表示する'),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppHeader(
          'お会計（一覧から選ぶ）',
          subtitle: '担当: ${widget.operatorName}',
          onBack: _leave,
          actions: [
            IconButton.outlined(
              tooltip: '担当者を変える',
              onPressed: _changeOperator,
              icon: const Icon(Icons.manage_accounts_outlined),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, box) => Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            color: AppColors.surface,
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                            child: Column(
                              children: [
                                TextField(
                                  controller: _searchController,
                                  decoration: InputDecoration(
                                    hintText: '商品名・商品コードで探す',
                                    prefixIcon: const Icon(Icons.search),
                                    contentPadding: EdgeInsets.zero,
                                    suffixIcon:
                                        _searchController.text.isNotEmpty
                                        ? IconButton(
                                            tooltip: '入力を消す',
                                            icon: const Icon(Icons.clear),
                                            onPressed: _searchController.clear,
                                          )
                                        : null,
                                  ),
                                ),
                                TabBar(
                                  controller: _tabController,
                                  tabs: [
                                    Tab(
                                      text:
                                          '商品（${_filteredProductItems.length}）',
                                    ),
                                    Tab(
                                      text:
                                          'セット（${_filteredBundleItems.length}）',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: TabBarView(
                              controller: _tabController,
                              children: [_buildProductTab(), _buildBundleTab()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: (box.maxWidth * 0.34).clamp(250, 380),
                      child: CartSummaryPanel(
                        itemCount: _totalItems,
                        total: _totalAmount,
                        tax: _totalTax,
                        promotionDiscount: _quote.promotionDiscount,
                        primaryLabel: _isClient ? 'ホスト機へ送る' : 'お会計へ',
                        primaryIcon: _isClient ? Icons.send : Icons.payments,
                        onPrimary: _totalItems == 0
                            ? null
                            : (_isClient ? _transferToHost : _subtotal),
                        actions: [
                          (
                            icon: Icons.delete_sweep_outlined,
                            label: 'すべて取り消す',
                            onTap: _totalItems == 0 ? null : _allClear,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
