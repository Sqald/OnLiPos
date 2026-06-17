import 'package:flutter/material.dart';
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

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _stocks;
    final q = _searchQuery.toLowerCase();
    return _stocks.where((s) {
      final name = (s['product_name'] as String? ?? '').toLowerCase();
      final code = (s['product_code'] as String? ?? '').toLowerCase();
      return name.contains(q) || code.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('在庫確認'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStocks,
            tooltip: '再読み込み',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: '商品名 / JANコードで絞り込み',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          if (!_isLoading && _errorMessage == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_filtered.length}件',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadStocks, child: const Text('再試行')),
          ],
        ),
      );
    }
    final items = _filtered;
    if (items.isEmpty) {
      return const Center(child: Text('在庫データがありません'));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final s = items[index];
        final qty = s['quantity'] as int? ?? 0;
        final isLow = qty <= 0;
        return ListTile(
          title: Text(s['product_name']?.toString() ?? ''),
          subtitle: Text(s['product_code']?.toString() ?? ''),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isLow ? Colors.red[50] : Colors.green[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isLow ? Colors.red : Colors.green,
              ),
            ),
            child: Text(
              '$qty',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isLow ? Colors.red : Colors.green[800],
              ),
            ),
          ),
        );
      },
    );
  }
}
