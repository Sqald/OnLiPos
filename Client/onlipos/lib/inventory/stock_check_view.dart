/// 在庫確認画面。
/// 店舗在庫の一覧をサーバーから取得し、商品名/JANコードで絞り込んで表示する。
library;

import 'package:material_ui/material_ui.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:onlipos/inventory/stock_check_api.dart';

class StockCheckView extends StatefulWidget {
  const StockCheckView({super.key});

  @override
  State<StockCheckView> createState() => _StockCheckViewState();
}

class _StockCheckViewState extends State<StockCheckView> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _stocks = [];
  String _searchQuery = '';
  final _searchController = TextEditingController();

  // 画面表示直後に在庫一覧を読み込む
  @override
  void initState() {
    super.initState();
    _loadStocks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// サーバーから在庫一覧を取得して画面状態を更新する
  Future<void> _loadStocks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await StockCheckApi.fetchStocks();

    if (!mounted) return;
    if (result['success'] == true) {
      final raw = (result['stocks'] as List?) ?? [];
      setState(() {
        _stocks = raw.cast<Map<String, dynamic>>();
        _isLoading = false;
      });
    } else {
      setState(() {
        _errorMessage = result['message']?.toString() ?? 'エラーが発生しました';
        _isLoading = false;
      });
    }
  }

  // 検索クエリで商品名/JANコードを絞り込んだ在庫一覧を返す
  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _stocks;
    final q = _searchQuery.toLowerCase();
    return _stocks.where((s) {
      final name = (s['product_name'] as String? ?? '').toLowerCase();
      final code = (s['product_code'] as String? ?? '').toLowerCase();
      return name.contains(q) || code.contains(q);
    }).toList();
  }

  // 検索バーと件数表示、在庫リスト本体をまとめた画面を構築する
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        '在庫を見る',
        actions: [
          OutlinedButton.icon(
            onPressed: _loadStocks,
            icon: const Icon(Icons.refresh, size: 20),
            label: const Text('最新にする'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '商品名・商品コードで探す',
                prefixIcon: const Icon(Icons.search),
                contentPadding: EdgeInsets.zero,
                suffixText: _isLoading ? null : '${_filtered.length}件　',
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  // 読込中/エラー/空データ/一覧表示の各状態に応じた本体ウィジェットを返す
  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return EmptyState(
        icon: Icons.cloud_off,
        title: '読み込めませんでした',
        message: _errorMessage,
        action: ElevatedButton(
          onPressed: _loadStocks,
          child: const Text('もう一度読み込む'),
        ),
      );
    }
    final items = _filtered;
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.warehouse_outlined,
        title: _searchQuery.isEmpty ? '在庫がまだ登録されていません' : '見つかりませんでした',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final s = items[index];
        final quantity = s['quantity'] as int? ?? 0;
        return Card(
          child: ListTile(
            title: Text(s['product_name']?.toString() ?? ''),
            subtitle: Text(s['product_code']?.toString() ?? ''),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (quantity <= 0)
                  const StatusBadge('在庫なし', type: MessageType.error),
                const SizedBox(width: 14),
                Text(
                  '$quantity 個',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: quantity <= 0 ? AppColors.danger : AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
