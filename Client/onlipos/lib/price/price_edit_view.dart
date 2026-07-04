import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onlipos/login/login_api.dart';
import 'package:onlipos/price/price_api.dart';
import 'package:onlipos/product/master_sync_api.dart';

class PriceEditView extends StatefulWidget {
  const PriceEditView({super.key});

  @override
  State<PriceEditView> createState() => _PriceEditViewState();
}

class _PriceEditViewState extends State<PriceEditView> {
  // 認証
  final _codeController = TextEditingController();
  final _pinController = TextEditingController();
  int? _employeeId;
  String? _employeeName;
  bool _authLoading = false;

  // 商品リスト
  final _searchController = TextEditingController();
  final List<Map<String, dynamic>> _products = [];
  bool _listLoading = false;
  bool _hasMore = false;
  int _lastId = 0;

  @override
  void dispose() {
    _codeController.dispose();
    _pinController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool get _authenticated => _employeeId != null;

  Future<void> _authenticate() async {
    final code = _codeController.text.trim();
    final pin = _pinController.text.trim();
    if (code.isEmpty || pin.isEmpty) {
      _showError('担当者コードとパスワードを入力してください');
      return;
    }
    setState(() => _authLoading = true);
    final result = await LoginApi.verifyEmployee(code: code, pin: pin);
    setState(() => _authLoading = false);

    if (result['success'] == true) {
      final permissions =
          (result['permissions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      if (!permissions.contains('edit_prices')) {
        _showError('この操作の権限がありません（店舗価格編集）');
        return;
      }
      setState(() {
        _employeeId = result['employee_id'] as int?;
        _employeeName = result['employee_name'] as String?;
      });
      _loadProducts(reset: true);
    } else {
      _showError(result['message']?.toString() ?? '認証に失敗しました');
    }
  }

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('価格を更新しました'),
          backgroundColor: Colors.green,
        ),
      );
      _resyncInBackground();
      _loadProducts(reset: true);
    } else {
      _showError(res['message']?.toString() ?? 'エラーが発生しました');
    }
  }

  void _resyncInBackground() async {
    const storage = FlutterSecureStorage();
    final baseUrl = await storage.read(key: 'AccessUrl') ?? '';
    final token = await storage.read(key: 'LoginToken') ?? '';
    final normalizedUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    try {
      await ProductSyncService(
        baseUrl: normalizedUrl,
        authToken: token,
      ).syncProducts();
    } catch (e) {
      debugPrint('Product sync error after price update: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('店舗価格設定')),
      body: _authenticated ? _buildPriceList() : _buildAuthForm(),
    );
  }

  Widget _buildAuthForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '担当者認証（店舗価格編集権限が必要です）',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: '担当者コード',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pinController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'パスワード',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _authenticate(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _authLoading ? null : _authenticate,
            child: _authLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('認証'),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'コード・商品名で検索',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
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
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _listLoading
                    ? null
                    : () => _loadProducts(reset: true),
                child: const Text('検索'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '担当: ${_employeeName ?? ''}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ),
        Expanded(
          child: _products.isEmpty && !_listLoading
              ? const Center(child: Text('商品が見つかりません'))
              : ListView.builder(
                  itemCount: _products.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _products.length) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: FilledButton(
                          onPressed: _listLoading
                              ? null
                              : () => _loadProducts(),
                          child: _listLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('さらに読み込む'),
                        ),
                      );
                    }
                    final p = _products[index];
                    final listPrice = (p['list_price'] as num?)?.toInt() ?? 0;
                    final storePrice = (p['store_price'] as num?)?.toInt();
                    final hasCustomPrice = storePrice != null;
                    return ListTile(
                      title: Text(p['name'] as String? ?? ''),
                      subtitle: Text(
                        '${p['code'] ?? ''}　'
                        '定価: ¥$listPrice　'
                        '${hasCustomPrice ? '店舗売価: ¥$storePrice' : '店舗売価: なし（定価を使用）'}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: '価格を編集',
                        onPressed: () => _editPrice(p),
                      ),
                      tileColor: hasCustomPrice
                          ? Colors.blue.withValues(alpha: 0.05)
                          : null,
                    );
                  },
                ),
        ),
        if (_listLoading && _products.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }
}

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
            '定価: ¥$listPrice',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          RadioGroup<String>(
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v!),
            child: Column(
              children: [
                RadioListTile<String>(
                  title: const Text('定価を使う'),
                  subtitle: Text('¥$listPrice が適用されます'),
                  value: 'list',
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<String>(
                  title: const Text('店舗売価を設定'),
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  void _save() {
    if (_mode == 'store') {
      final amount = int.tryParse(_amountController.text.trim());
      if (amount == null || amount < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('0以上の正しい金額を入力してください'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      Navigator.pop(context, {'mode': 'store', 'amount': amount});
    } else {
      Navigator.pop(context, {'mode': 'list'});
    }
  }
}
