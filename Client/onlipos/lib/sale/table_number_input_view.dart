import 'package:material_ui/material_ui.dart';
import 'package:onlipos/ui/num_pad.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:flutter/services.dart';

import 'sale_scan_view.dart';
import 'table_order_api.dart';
import 'table_order_store.dart';

/// 飲食店モード用の卓番入力画面。
/// 担当者ログイン後に表示され、卓番を入力すると SaleScanView に遷移する。
/// サーバーから取得した注文中テーブルをクイック選択ボタンとして表示する。
class TableNumberInputView extends StatefulWidget {
  final String operatorName;
  final int operatorId;

  const TableNumberInputView({
    super.key,
    required this.operatorName,
    required this.operatorId,
  });

  @override
  State<TableNumberInputView> createState() => _TableNumberInputViewState();
}

class _TableNumberInputViewState extends State<TableNumberInputView> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<String> _activeTables = [];
  bool _isLoadingTables = true;

  @override
  void initState() {
    super.initState();
    _loadActiveTables();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // 注文中テーブル一覧をサーバー（失敗時はローカルストア）から取得する
  Future<void> _loadActiveTables() async {
    List<String> tables = [];
    try {
      tables = await TableOrderApi.getActiveTables();
    } catch (_) {
      // フォールバック：ローカルストア
      tables = TableOrderStore().activeTables;
    }
    if (mounted) {
      setState(() {
        _activeTables = tables;
        _isLoadingTables = false;
      });
      _focusNode.requestFocus();
    }
  }

  // 入力/選択された卓番でSaleScanView（飲食店モード）に遷移する
  void _openTable(String tableNumber) {
    final trimmed = tableNumber.trim();
    if (trimmed.isEmpty) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => SaleScanView(
          operatorName: widget.operatorName,
          operatorId: widget.operatorId,
          storeMode: 'restaurant',
          tableNumber: trimmed,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final input = SectionCard(
      title: '卓の番号を入力',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            keyboardType: TextInputType.none,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(labelText: '卓'),
            onSubmitted: _openTable,
          ),
          const SizedBox(height: 10),
          NumPad(controller: _controller, maxLength: 4, keyHeight: 54),
          const SizedBox(height: 10),
          SizedBox(
            height: 60,
            child: ElevatedButton(
              onPressed: () => _openTable(_controller.text),
              child: const Text('この卓を開く', style: TextStyle(fontSize: 20)),
            ),
          ),
        ],
      ),
    );
    final tables = SectionCard(
      title: '注文中の卓',
      child: _isLoadingTables
          ? const Center(child: CircularProgressIndicator())
          : _activeTables.isEmpty
          ? const Text(
              '注文中の卓はありません',
              style: TextStyle(color: AppColors.secondary),
            )
          : Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final table in _activeTables)
                  SizedBox(
                    width: 116,
                    height: 76,
                    child: OutlinedButton(
                      onPressed: () => _openTable(table),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: AppColors.warningSoft,
                        foregroundColor: AppColors.warning,
                      ),
                      child: Text(
                        '卓 $table',
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
    return Scaffold(
      appBar: AppHeader('卓を選ぶ', subtitle: '担当: ${widget.operatorName}'),
      body: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: box.maxWidth < 720
              ? Column(children: [input, const SizedBox(height: 12), tables])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 340, child: input),
                    const SizedBox(width: 16),
                    Expanded(child: tables),
                  ],
                ),
        ),
      ),
    );
  }
}
