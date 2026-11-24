/// 店舗価格設定画面。「edit_prices」権限を持つ担当者で認証したうえで、
/// 商品ごとに定価を使うか店舗独自の売価を設定するかを編集する。
/// 更新後はバックグラウンドで商品マスタの再同期も行う。
library;

import 'package:material_ui/material_ui.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:onlipos/login/operator_sign_in_panel.dart';
import 'package:onlipos/api/pos_api_client.dart';
import 'package:onlipos/price/price_api.dart';
import 'package:onlipos/product/master_sync_api.dart';

class PriceEditView extends StatefulWidget {
  const PriceEditView({super.key});

  @override
  State<PriceEditView> createState() => _PriceEditViewState();
}

class _PriceEditViewState extends State<PriceEditView> {
  // 認証
  int? _employeeId;
  String? _employeeName;

  // 商品リスト
  final _searchController = TextEditingController();
  final List<Map<String, dynamic>> _products = [];
  bool _listLoading = false;
  bool _hasMore = false;
  int _lastId = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _authenticated => _employeeId != null;

  // 商品価格一覧を取得する。resetがtrueなら検索条件をリセットして先頭から取得する
  Future<void> _loadProducts({bool reset = false}) async {
    if (_listLoading) return;
    final query = _searchController.text.trim();
    final lastId = reset ? 0 : _lastId;

    setState(() {
      _listLoading = true;
      if (reset) {
        _products.clear();
        _lastId = 0;
      }
    });

    final result = await PriceApi.fetchStorePrices(
      employeeId: _employeeId!,
      query: query,
      lastId: lastId,
    );

    setState(() => _listLoading = false);

    if (result['success'] == true) {
      final items = (result['products'] as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _products.addAll(items);
        _hasMore = result['has_more'] == true;
        _lastId = (result['last_id'] as num?)?.toInt() ?? _lastId;
      });
    } else {
      _showError(result['message']?.toString() ?? 'エラーが発生しました');
    }
  }

  // 価格編集ダイアログを開き、選択結果に応じて店舗価格を更新する
  Future<void> _editPrice(Map<String, dynamic> product) async {
    final choice = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PriceEditDialog(product: product),
    );
    if (choice == null || !mounted) return;

    final res = await PriceApi.updateStorePrice(
      employeeId: _employeeId!,
      productId: product['product_id'] as int,
      mode: choice['mode'] as String,
      amount: choice['amount'] as int?,
    );

    if (!mounted) return;

    if (res['success'] == true) {
      showMessage(context, '価格を更新しました', MessageType.success);
      _resyncInBackground();
      _loadProducts(reset: true);
    } else {
      _showError(res['message']?.toString() ?? 'エラーが発生しました');
    }
  }

  // 価格更新後、端末の商品マスタをバックグラウンドで再同期する
  void _resyncInBackground() async {
    try {
      final creds = await PosApiClient.credentials();
      await ProductSyncService(
        baseUrl: creds.baseUrl,
        authToken: creds.token,
      ).syncProducts();
    } catch (e) {
      debugPrint('Product sync error after price update: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    showMessage(context, msg, MessageType.error);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        '店舗の価格',
        subtitle: _employeeName == null ? null : '担当: $_employeeName',
      ),
      body: _authenticated
          ? _buildPriceList()
          : OperatorSignInPanel(
              icon: Icons.price_change,
              message: 'この店舗の値段を変えるには、「店舗価格編集」の権限を持つ人の確認が必要です。',
              permission: 'edit_prices',
              onAuthenticated: (id, name) {
                setState(() {
                  _employeeId = id;
                  _employeeName = name;
                });
                _loadProducts(reset: true);
              },
            ),
    );
  }

  // 検索欄と商品価格一覧（続きはボタンで読み込む）
  Widget _buildPriceList() {
    return Column(
      children: [
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '商品名・商品コードで探す',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: '入力を消す',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _loadProducts(reset: true);
                      },
                    ),
                  ),
                  onSubmitted: (_) => _loadProducts(reset: true),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _listLoading
                    ? null
                    : () => _loadProducts(reset: true),
                child: const Text('探す'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _products.isEmpty
              ? (_listLoading
                    ? const Center(child: CircularProgressIndicator())
                    : const EmptyState(
                        icon: Icons.search_off,
                        title: '商品が見つかりませんでした',
                      ))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _products.length + (_hasMore ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    if (index == _products.length) {
                      return OutlinedButton(
                        onPressed: _listLoading ? null : () => _loadProducts(),
                        child: Text(_listLoading ? '読み込んでいます…' : '続きを読み込む'),
                      );
                    }
                    final p = _products[index];
                    final listPrice = (p['list_price'] as num?)?.toInt() ?? 0;
                    final storePrice = (p['store_price'] as num?)?.toInt();
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        title: Text(p['name'] as String? ?? ''),
                        subtitle: Text(
                          '${p['code'] ?? ''}　基本価格 ${yen(listPrice)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (storePrice != null)
                              const StatusBadge(
                                'この店舗の価格',
                                type: MessageType.warning,
                              ),
                            const SizedBox(width: 12),
                            Text(
                              yen(storePrice ?? listPrice),
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.edit_outlined),
                          ],
                        ),
                        onTap: () => _editPrice(p),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// 個別商品の価格を「定価を使う」/「店舗売価を設定」から選択して編集するダイアログ
class _PriceEditDialog extends StatefulWidget {
  final Map<String, dynamic> product;
  const _PriceEditDialog({required this.product});

  @override
  State<_PriceEditDialog> createState() => _PriceEditDialogState();
}

class _PriceEditDialogState extends State<_PriceEditDialog> {
  late String _mode;
  final _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final storePrice = (widget.product['store_price'] as num?)?.toInt();
    _mode = storePrice != null ? 'store' : 'list';
    if (storePrice != null) {
      _amountController.text = storePrice.toString();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listPrice = (widget.product['list_price'] as num?)?.toInt() ?? 0;
    return AlertDialog(
      title: Text(widget.product['name'] as String? ?? ''),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '基本価格 ${yen(listPrice)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          RadioGroup<String>(
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v!),
            child: Column(
              children: [
                RadioListTile<String>(
                  title: const Text('基本価格のまま売る'),
                  subtitle: Text(yen(listPrice)),
                  value: 'list',
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<String>(
                  title: const Text('この店舗だけ値段を変える'),
                  value: 'store',
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          if (_mode == 'store') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '金額（円）',
                border: OutlineInputBorder(),
                prefixText: '¥ ',
              ),
            ),
          ],
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('やめる'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  // 入力内容を検証し、選択結果をダイアログの呼び出し元に返す
  void _save() {
    if (_mode == 'store') {
      final amount = int.tryParse(_amountController.text.trim());
      if (amount == null || amount < 0) {
        showMessage(context, '0以上の正しい金額を入力してください', MessageType.error);
        return;
      }
      Navigator.pop(context, {'mode': 'store', 'amount': amount});
    } else {
      Navigator.pop(context, {'mode': 'list'});
    }
  }
}
