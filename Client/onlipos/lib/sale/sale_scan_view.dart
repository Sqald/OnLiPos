// バーコードスキャン方式の売上登録画面（会計のメイン画面）。
// ハードウェアバーコードスキャナからのキー入力をバッファリングして商品を検索・
// カートに追加し、店舗モード（標準/飲食店/小売店）ごとにテーブル注文・保留・
// クライアント→ホスト転送といった機能を切り替える。
import 'package:material_ui/material_ui.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:onlipos/ui/amount_dialog.dart';
import 'package:onlipos/sale/cart_panel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onlipos/login/operator_input_view.dart';
import 'package:onlipos/product/catalog_service.dart';
import 'package:onlipos/product/product.dart';
import 'package:onlipos/product/product_repository.dart';
import 'package:onlipos/sale/cart_pricing.dart';
import 'package:onlipos/sale/customer_display.dart';
import 'package:onlipos/sale/option_select_dialog.dart';
import 'package:onlipos/sale/payment_view.dart';
import 'package:onlipos/sale/sale_extras_api.dart';
import 'package:onlipos/sale/send_to_api.dart';
import 'package:onlipos/sale/sale_item.dart';
import 'package:onlipos/sale/table_order_store.dart';
import 'package:onlipos/sale/hold_order_store.dart';
import 'package:onlipos/sale/table_order_api.dart';
import 'package:onlipos/sale/hold_order_api.dart';
import 'package:onlipos/sale/transfer_order_api.dart';
import 'package:onlipos/product/product_lookup_api.dart';
import 'package:onlipos/sale/escpos/lan_recipt_api.dart';
import 'package:onlipos/sale/price_edit_dialog.dart';
import 'package:onlipos/sale/weight_input_dialog.dart';

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
  // 自動値引き・税の端数処理の設定（読み込み完了までは値引きなしで計算する）
  CartPricing _pricing = const CartPricing();
  int _promotionDiscount = 0;
  // 店内飲食（飲食店モードの既定）/ 持ち帰り
  late bool _eatIn = widget.storeMode == 'restaurant';
  // 厨房へ送信済みの数量（商品名・オプションごと）
  final Map<String, int> _sentToKitchen = {};

  bool get _isRestaurant => widget.storeMode == 'restaurant';
  bool get _isRetail => widget.storeMode == 'retail';
  bool get _isClient => _posRole == 'client';

  @override
  void initState() {
    super.initState();
    _loadPosRole();
    _loadPricing();
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

  Future<void> _loadPricing() async {
    final pricing = await CatalogService.instance.cartPricing();
    if (!mounted) return;
    setState(() {
      _pricing = pricing;
      _calculateTotals();
    });
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

  // バーコードから商品またはセット商品を検索し、カートに追加/数量加算する。
  // ローカルに見つからない場合はサーバー問い合わせを提案する。
  Future<void> _onBarcodeScanned(String barcode) async {
    if (barcode.isEmpty) return;

    final product = await _productRepository.findProductByCode(barcode);
    if (product != null) {
      await _addProduct(product);
      return;
    }

    final bundle = await _productRepository.findBundleByCode(barcode);
    if (bundle != null) {
      final item = await _productRepository.bundleItem(bundle);
      if (item == null) {
        _showNotFound(barcode);
        return;
      }
      setState(() {
        final existing = _scannedItems
            .where(
              (s) =>
                  s.isBundle &&
                  s.bundleCode == bundle.code &&
                  s.overridePrice == null,
            )
            .firstOrNull;
        if (existing != null) {
          existing.quantity++;
        } else {
          _scannedItems.insert(0, item);
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

  // 商品をカートに加える。量り売り・オプション・バリエーションがあれば選択してから加える
  Future<void> _addProduct(Product product) async {
    if (product.soldByWeight) return _addWeightedProduct(product);

    List<OptionItem> options = const [];
    if (product.optionGroups.isNotEmpty) {
      final selected = await showOptionSelectDialog(context, product);
      if (!mounted) return;
      if (selected == null) {
        _focusNode.requestFocus();
        return;
      }
      options = selected;
    }

    setState(() {
      final existing = options.isEmpty
          ? _scannedItems
                .where((item) => item.canMerge(product, eatIn: _eatIn))
                .firstOrNull
          : null;
      if (existing != null) {
        existing.quantity++;
      } else {
        _scannedItems.insert(
          0,
          ScannedItem(product: product, eatIn: _eatIn, options: options),
        );
      }
      _calculateTotals();
    });
    _triggerTableSave();
    _focusNode.requestFocus();
  }

  void _showNotFound(String barcode) {
    showMessage(context, '商品が見つかりません（$barcode）', MessageType.error);
    _focusNode.requestFocus();
  }

  Future<void> _askAndLookupFromServer(String barcode) async {
    final shouldQuery = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('商品が見つかりません'),
        content: Text('「$barcode」はこの端末に登録されていません。\n最新の商品データを確認しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('やめる'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('確認する'),
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
      await _addProduct(product);
    } catch (e) {
      if (!mounted) return;
      showMessage(context, '商品データを確認できませんでした: $e', MessageType.error);
    }
    _focusNode.requestFocus();
  }

  // カート内の合計点数・合計金額・合計消費税を再計算する
  void _calculateTotals() {
    final quote = _pricing.quote(_scannedItems);
    _totalItems = quote.itemCount;
    _totalAmount = quote.total;
    _totalTax = quote.tax;
    _promotionDiscount = quote.promotionDiscount;
    CustomerDisplay.update(_scannedItems, quote.total);
  }

  // 店内飲食と持ち帰りを切り替える（税率・価格が変わる）
  void _toggleEatIn(bool eatIn) {
    setState(() {
      _eatIn = eatIn;
      for (final item in _scannedItems) {
        item.eatIn = eatIn;
      }
      _calculateTotals();
    });
    _triggerTableSave();
    _focusNode.requestFocus();
  }

  // まだ送っていない注文を厨房へ送る
  Future<void> _sendToKitchen() async {
    final pending = <Map<String, dynamic>>[];
    final totals = <String, int>{};
    for (final item in _scannedItems) {
      final options = item.options.map((o) => o.name).toList();
      final name = item.bundleName ?? item.product.name;
      final key = '$name|${options.join(',')}';
      totals[key] = (totals[key] ?? 0) + item.quantity;
      final rest = totals[key]! - (_sentToKitchen[key] ?? 0);
      if (rest > 0) {
        pending.add({
          'product_id': item.product.id,
          'name': name,
          'quantity': rest > item.quantity ? item.quantity : rest,
          'options': options,
        });
      }
    }
    if (pending.isEmpty) return;
    final result = await SaleExtrasApi.sendKitchen(
      requestId: SentToApi.newRequestId(),
      tableNumber: widget.tableNumber,
      items: pending,
    );
    if (!mounted) return;
    final ok = result['success'] == true;
    if (ok) {
      _sentToKitchen
        ..clear()
        ..addAll(totals);
    }
    showMessage(
      context,
      ok ? '厨房へ送りました' : result['message']?.toString() ?? '送信に失敗しました',
      ok ? MessageType.success : MessageType.error,
    );
    _focusNode.requestFocus();
  }

  // 商品マスタが更新されたら、カートの商品を新しい価格・税率に置き換える
  Future<void> _refreshCart() async {
    final refreshed = <ScannedItem>[];
    for (final item in _scannedItems) {
      final ScannedItem? fresh;
      if (item.isBundle) {
        final bundle = await _productRepository.findBundleByCode(
          item.bundleCode!,
        );
        fresh = bundle == null
            ? null
            : await _productRepository.bundleItem(
                bundle,
                quantity: item.quantity,
              );
      } else {
        final product = await _productRepository.findProductByCode(
          item.product.code,
        );
        fresh = product == null
            ? null
            : (ScannedItem.fromJson({
                ...item.toJson(),
                'product': product.toMap(),
              }));
      }
      if (fresh != null) refreshed.add(fresh);
    }
    await _loadPricing();
    if (!mounted) return;
    setState(() {
      _scannedItems
        ..clear()
        ..addAll(refreshed);
      _calculateTotals();
    });
  }

  // ---- 量り売り（計量）商品 ------------------------------------------

  /// 量り売り商品は数量ではなく重量(g)から金額を算出するため、
  /// 個数の自動マージは行わず、重量入力ダイアログを経て常に新しい行を追加する。
  Future<void> _addWeightedProduct(Product product) async {
    if (!mounted) return;
    final grams = await showDialog<int>(
      context: context,
      builder: (ctx) => WeightInputDialog(product: product),
    );
    if (grams == null || !mounted) {
      _focusNode.requestFocus();
      return;
    }
    setState(() {
      _scannedItems.insert(
        0,
        ScannedItem(product: product, weightGrams: grams, eatIn: _eatIn),
      );
      _calculateTotals();
    });
    _triggerTableSave();
    _focusNode.requestFocus();
  }

  // 明細行を長押し/タップした際に価格変更ダイアログを開き、上書き価格を反映する
  Future<void> _editItemPrice(int index) async {
    final item = _scannedItems[index];
    // セット商品の価格は変更しない（小計割引を使う）
    if (item.isBundle) return;
    final result = await showDialog<({int price, String? reason})>(
      context: context,
      builder: (ctx) => PriceEditDialog(product: item.product),
    );

    if (result == null || !mounted) {
      _focusNode.requestFocus();
      return;
    }
    setState(() {
      final newPrice = result.price;
      final newOverride = newPrice == item.product.price ? null : newPrice;
      item.overridePrice = newOverride;
      item.discountReason = newOverride != null ? result.reason : null;
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

  // カートを空にする（担当者はそのまま続けて会計できる）
  Future<void> _allClear() async {
    if (_scannedItems.isEmpty) return;
    final ok = await confirm(
      context,
      title: '商品をすべて取り消しますか？',
      message: '登録した$_totalItems点を取り消します。',
      okLabel: 'すべて取り消す',
      danger: true,
    );
    if (ok && mounted) {
      if (_isRestaurant && widget.tableNumber != null) {
        TableOrderApi.clearTable(widget.tableNumber!).catchError((_) {
          TableOrderStore().clearTable(widget.tableNumber!);
        });
      }
      setState(() {
        _sentToKitchen.clear();
        _scannedItems.clear();
        _calculateTotals();
      });
    }
    _focusNode.requestFocus();
  }

  // 商品が残っているときは、消えることを確認してから画面を離れる
  // （飲食店モードの注文は卓ごとに保存されるため確認しない）
  Future<bool> _confirmLeave() async {
    if (_scannedItems.isEmpty || _isRestaurant) return true;
    final ok = await confirm(
      context,
      title: '会計をやめますか？',
      message: '登録した$_totalItems点は取り消されます。',
      okLabel: '会計をやめる',
      cancelLabel: '会計を続ける',
      danger: true,
    );
    if (!ok) _focusNode.requestFocus();
    return ok;
  }

  Future<void> _leave() async {
    if (!await _confirmLeave() || !mounted) return;
    CustomerDisplay.update(const [], 0);
    Navigator.of(context).pop();
  }

  // 担当者を変える
  Future<void> _changeOperator() async {
    if (!await _confirmLeave() || !mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const OperatorInputView()),
    );
  }

  // バーコードが読めないときに、商品コードを手で入力する
  Future<void> _inputCode() async {
    final code = await showNumberDialog(
      context,
      title: '商品コードを入力',
      message: 'バーコードの下に書かれた番号を入力してください',
      okLabel: '登録する',
      maxLength: 20,
      allowLetters: true,
    );
    if (!mounted) return;
    if (code != null) await _onBarcodeScanned(code);
    _focusNode.requestFocus();
  }

  // カート内容を明細に変換し、決済画面へ遷移する。会計確定後はカート/テーブル注文をクリアする
  Future<void> _subtotal() async {
    if (_scannedItems.isEmpty) return;

    final String? extraInfo = _isRestaurant && widget.tableNumber != null
        ? '卓 ${widget.tableNumber}'
        : null;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentView(
          operatorName: widget.operatorName,
          operatorId: widget.operatorId,
          items: _scannedItems,
          pricing: _pricing,
          extraInfo: extraInfo,
        ),
      ),
    );

    _focusNode.requestFocus();

    if (result == 'master_updated') await _refreshCart();
    if (result == true) {
      _sentToKitchen.clear();
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

  // カートが空なら保留呼び出しダイアログ、商品があれば現在のカートを保留にする
  void _holdOrRecall() {
    if (_scannedItems.isEmpty) {
      _showHoldRecallDialog();
    } else {
      _holdCurrentOrder();
    }
  }

  // 現在のカートをサーバー（失敗時はローカル）に保留として保存し、保留票を印刷する
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
      showMessage(context, '保留番号 $holdNumber で保留しました', MessageType.warning);
    }
    _focusNode.requestFocus();
  }

  void _showHoldRecallDialog() {
    showDialog(
      context: context,
      builder: (_) => _HoldRecallDialog(
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
              showMessage(
                context,
                '保留番号 $holdNumber が見つかりません',
                MessageType.error,
              );
            }
            return;
          }
          if (!mounted) return;
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

    try {
      final transferId = await TransferOrderApi.createTransfer(
        operatorName: widget.operatorName,
        operatorId: widget.operatorId,
        totalAmount: _totalAmount,
        items: _scannedItems,
        tableNumber: widget.tableNumber,
      );

      setState(() {
        _scannedItems.clear();
        _calculateTotals();
      });

      if (mounted) {
        showMessage(context, '転送しました（転送ID: $transferId）', MessageType.success);
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, '転送に失敗しました: $e', MessageType.error);
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

  @override
  Widget build(BuildContext context) {
    final header = AppHeader(
      _isRestaurant && widget.tableNumber != null
          ? '卓 ${widget.tableNumber}'
          : 'お会計',
      subtitle: '担当: ${widget.operatorName}',
      onBack: _leave,
      actions: _isLoadingTable
          ? const []
          : [
              if (_isRestaurant) ...[
                OutlinedButton.icon(
                  onPressed: _scannedItems.isEmpty ? null : _sendToKitchen,
                  icon: const Icon(Icons.restaurant, size: 20),
                  label: const Text('厨房へ送る'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(64, 44),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('店内')),
                  ButtonSegment(value: false, label: Text('持ち帰り')),
                ],
                selected: {_eatIn},
                onSelectionChanged: (v) => _toggleEatIn(v.first),
              ),
              const SizedBox(width: 10),
              IconButton.outlined(
                tooltip: '担当者を変える',
                onPressed: _changeOperator,
                icon: const Icon(Icons.manage_accounts_outlined),
              ),
            ],
    );
    if (_isLoadingTable) {
      return Scaffold(
        appBar: header,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          appBar: header,
          body: GestureDetector(
            onTap: () => _focusNode.requestFocus(),
            child: LayoutBuilder(
              builder: (context, box) => Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildCart()),
                  SizedBox(
                    width: (box.maxWidth * 0.36).clamp(250, 400),
                    child: CartSummaryPanel(
                      itemCount: _totalItems,
                      total: _totalAmount,
                      tax: _totalTax,
                      promotionDiscount: _promotionDiscount,
                      primaryLabel: _isClient ? 'ホスト機へ送る' : 'お会計へ',
                      primaryIcon: _isClient ? Icons.send : Icons.payments,
                      onPrimary: _scannedItems.isEmpty
                          ? null
                          : (_isClient ? _transferToHost : _subtotal),
                      actions: [
                        (
                          icon: Icons.dialpad,
                          label: 'コードを入力',
                          onTap: _inputCode,
                        ),
                        if (_isRetail && !_isClient)
                          (
                            icon: _scannedItems.isEmpty
                                ? Icons.call_received
                                : Icons.pause_circle_outline,
                            label: _scannedItems.isEmpty ? '保留を呼び出す' : '保留する',
                            onTap: _holdOrRecall,
                          ),
                        (
                          icon: Icons.delete_sweep_outlined,
                          label: 'すべて取り消す',
                          onTap: _scannedItems.isEmpty ? null : _allClear,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 登録した商品の一覧（新しいものが上）
  Widget _buildCart() {
    if (_scannedItems.isEmpty) {
      return EmptyState(
        icon: Icons.qr_code_scanner,
        title: '商品のバーコードを読み取ってください',
        message: '読み取れないときは、番号を入力して登録できます',
        action: OutlinedButton.icon(
          onPressed: _inputCode,
          icon: const Icon(Icons.dialpad),
          label: const Text('商品コードを入力する'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _scannedItems.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _buildCartRow(index),
    );
  }

  Widget _buildCartRow(int index) {
    final item = _scannedItems[index];
    final changed = item.overridePrice != null || item.promotionPrice != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.options.isEmpty
                        ? item.product.name
                        : '${item.product.name}（${item.options.map((o) => o.name).join('・')}）',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (item.bundleCode != null)
                        const StatusBadge('セット', type: MessageType.warning),
                      if (changed)
                        Text(
                          yen(item.regularPrice),
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.muted,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      Text(
                        yen(item.price),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: changed
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: changed ? AppColors.danger : null,
                        ),
                      ),
                      if (item.weightGrams != null)
                        Text('${item.weightGrams}g'),
                      if (changed)
                        StatusBadge(
                          item.promotionName ?? item.discountReason ?? '値段を変更',
                          type: MessageType.error,
                        ),
                      Text(
                        '税${item.taxRate}%',
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
            if (!item.isBundle)
              IconButton(
                tooltip: '値段を変える',
                onPressed: () => _editItemPrice(index),
                icon: const Icon(Icons.sell_outlined),
              ),
            QuantityStepper(
              quantity: item.quantity,
              removeOnMinus: item.quantity <= 1,
              onMinus: () => _decrementItem(index),
              onPlus: () => _incrementItem(index),
            ),
            SizedBox(
              width: 104,
              child: Text(
                yen(item.subtotal),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: changed ? AppColors.danger : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
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
      title: const Text('保留を呼び出す'),
      content: SizedBox(
        width: 420,
        child: _isLoading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_holds.isNotEmpty) ...[
                      const Text(
                        '保留中の注文',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
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
                                  color: Colors.purple[900],
                                ),
                              ),
                            ),
                            title: Text('担当: ${hold.operatorName}'),
                            subtitle: Text(
                              '${yen(hold.totalAmount)}　${hold.createdAt.toLocal().toString().substring(11, 16)}',
                            ),
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
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      autofocus: _holds.isEmpty,
                      decoration: const InputDecoration(
                        labelText: '保留番号',
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
          child: const Text('やめる'),
        ),
        ElevatedButton(onPressed: _confirm, child: const Text('呼び出す')),
      ],
    );
  }
}
