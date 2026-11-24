/// POP(値札)印刷画面。JANコードまたは商品名で商品を検索して印刷リストに追加し、
/// 面付け数を選んでプレビュー表示または直接印刷する。
library;

import 'package:flutter/material.dart';
import 'package:onlipos/sale/cart_panel.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_header.dart';
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
        showMessage(context, '商品が見つかりませんでした: $code', MessageType.info);
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
      showMessage(context, '印刷リストが空です', MessageType.error);
      return;
    }
    final items = List<PopItem>.from(_items);
    final perPage = _perPage;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: const AppHeader('POPの確認'),
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
      showMessage(context, '印刷リストが空です', MessageType.error);
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
      appBar: const AppHeader('POP印刷', subtitle: '印刷する商品を選んでください'),
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
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
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
                      labelText: '商品コード（バーコード）',
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
                  label: const Text('足す'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 商品名検索
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '商品名で探す',
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
                        subtitle: Text('${yen(p.price)}　${p.code}'),
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

  // 印刷する商品の一覧（枚数の増減）
  Widget _buildPrintList() {
    if (_items.isEmpty) {
      return const EmptyState(
        icon: Icons.local_offer_outlined,
        title: '商品を足してください',
        message: 'バーコードを読み取るか、商品名で探します',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final item = _items[i];
        return Card(
          child: ListTile(
            title: Text(item.product.name),
            subtitle: Text('${yen(item.product.price)}　${item.product.code}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                QuantityStepper(
                  quantity: item.count,
                  removeOnMinus: item.count <= 1,
                  onMinus: () =>
                      item.count <= 1 ? _removeItem(i) : _updateCount(i, -1),
                  onPlus: () => _updateCount(i, 1),
                ),
                const Text('枚'),
              ],
            ),
          ),
        );
      },
    );
  }

  // 1ページに並べる枚数と、確認・印刷のボタン
  Widget _buildBottomBar() {
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('1ページに'),
              const SizedBox(width: 10),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 1, label: Text('1枚')),
                  ButtonSegment(value: 2, label: Text('2枚')),
                  ButtonSegment(value: 4, label: Text('4枚')),
                  ButtonSegment(value: 8, label: Text('8枚')),
                  ButtonSegment(value: 16, label: Text('16枚')),
                ],
                selected: {_perPage},
                onSelectionChanged: (s) => setState(() => _perPage = s.first),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: _items.isEmpty ? null : _showPreview,
                icon: const Icon(Icons.preview),
                label: const Text('確認する'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _items.isEmpty ? null : _print,
                icon: const Icon(Icons.print),
                label: const Text('印刷する'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
