/// POP(値札)印刷画面。JANコードまたは商品名で商品を検索して印刷リストに追加し、
/// 面付け数を選んでプレビュー表示または直接印刷する。
library;

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:onlipos/pop/pop_pdf_builder.dart';
import 'package:onlipos/product/product.dart';
import 'package:onlipos/product/product_repository.dart';

class PopView extends StatefulWidget {
  final ProductRepository? repo;

  const PopView({super.key, this.repo});

  @override
  State<PopView> createState() => _PopViewState();
}

class _PopViewState extends State<PopView> {
  late final ProductRepository _repo;
  final _janCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  final List<PopItem> _items = [];
  List<Product> _searchResults = [];
  bool _searching = false;
  int _perPage = 4;

  @override
  void initState() {
    super.initState();
    _repo = widget.repo ?? ProductRepository();
  }

  @override
  void dispose() {
    _janCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  // JANコードで商品を検索し、見つかれば印刷リストに追加する
  Future<void> _searchByJan() async {
    final code = _janCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _searching = true);
    try {
      final p = await _repo.findProductByCode(code);
      if (!mounted) return;
      if (p != null) {
        _addProduct(p);
        _janCtrl.clear();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('商品が見つかりませんでした: $code')));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  // 商品名の部分一致検索を行い、結果をドロップダウンに表示する
  Future<void> _searchByName(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    final results = await _repo.searchByName(query);
    if (mounted) setState(() => _searchResults = results);
  }

  // 商品を印刷リストに追加する(既存なら枚数をインクリメント)
  void _addProduct(Product p) {
    setState(() {
      final idx = _items.indexWhere((e) => e.product.id == p.id);
      if (idx >= 0) {
        _items[idx].count++;
      } else {
        _items.add(PopItem(product: p));
      }
      _searchResults = [];
    });
    _nameCtrl.clear();
  }

  void _removeItem(int idx) => setState(() => _items.removeAt(idx));

  void _updateCount(int idx, int delta) {
    setState(() {
      _items[idx].count = (_items[idx].count + delta).clamp(1, 99);
    });
  }

  // PDFプレビュー画面を表示する
  Future<void> _showPreview() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('印刷リストが空です')));
      return;
    }
    final items = List<PopItem>.from(_items);
    final perPage = _perPage;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('POP印刷プレビュー')),
          body: PdfPreview(
            build: (_) => PopPdfBuilder.build(items, perPage),
            allowPrinting: true,
            allowSharing: true,
          ),
        ),
      ),
    );
  }

  // プレビューを経由せず直接印刷する
  Future<void> _print() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('印刷リストが空です')));
      return;
    }
    final items = List<PopItem>.from(_items);
    final perPage = _perPage;
    await Printing.layoutPdf(
      onLayout: (_) => PopPdfBuilder.build(items, perPage),
      name: 'POP_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1D1D1D),
      appBar: AppBar(
        title: const Text('POP印刷'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildSearchSection(),
          Expanded(child: _buildPrintList()),
          _buildBottomBar(),
        ],
      ),
    );
  }

  // JANコード検索・商品名検索の入力欄と検索結果ドロップダウンをまとめたカード
  Widget _buildSearchSection() {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // JAN コード検索
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _janCtrl,
                    decoration: const InputDecoration(
                      labelText: 'JANコード',
                      prefixIcon: Icon(Icons.qr_code),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    onSubmitted: (_) => _searchByJan(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _searching ? null : _searchByJan,
                  icon: const Icon(Icons.search),
                  label: const Text('検索'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 商品名検索
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '商品名で検索',
                prefixIcon: Icon(Icons.manage_search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _searchByName,
            ),
            // 検索結果ドロップダウン
            if (_searchResults.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                margin: const EdgeInsets.only(top: 4),
                child: Material(
                  color: Colors.white,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = _searchResults[i];
                      return ListTile(
                        dense: true,
                        title: Text(p.name),
                        subtitle: Text('¥${p.price}  ${p.code}'),
                        trailing: const Icon(Icons.add_circle_outline),
                        onTap: () => _addProduct(p),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 印刷対象として追加した商品の一覧(枚数増減・削除操作つき)
  Widget _buildPrintList() {
    if (_items.isEmpty) {
      return const Center(
        child: Text('商品を追加してください', style: TextStyle(color: Colors.white54)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final item = _items[i];
        final p = item.product;
        return Card(
          child: ListTile(
            title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('¥${p.price}  ${p.code}'),
            leading: const Icon(Icons.crop_portrait, size: 36),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: '枚数を減らす',
                  onPressed: () => _updateCount(i, -1),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    '${item.count}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: '枚数を増やす',
                  onPressed: () => _updateCount(i, 1),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: '削除',
                  onPressed: () => _removeItem(i),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 面付け数の選択とプレビュー/印刷ボタンを配置する下部バー
  Widget _buildBottomBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '面付け（1ページ当たりの枚数）:',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1面')),
              ButtonSegment(value: 2, label: Text('2面')),
              ButtonSegment(value: 4, label: Text('4面')),
              ButtonSegment(value: 8, label: Text('8面')),
              ButtonSegment(value: 16, label: Text('16面')),
            ],
            selected: {_perPage},
            onSelectionChanged: (s) => setState(() => _perPage = s.first),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return const Color(0xFF2D89EF);
                }
                return Colors.grey[800];
              }),
              foregroundColor: WidgetStateProperty.all(Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showPreview,
                  icon: const Icon(Icons.preview),
                  label: const Text('プレビュー'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _print,
                  icon: const Icon(Icons.print),
                  label: const Text('印刷'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D89EF),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
