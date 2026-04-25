import 'package:flutter/material.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: Text('卓番入力 - 担当: ${widget.operatorName}'),
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '戻る',
                onPressed: () => Navigator.pop(context),
              )
            : null,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              const Text(
                '卓番を入力してください',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 56, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '卓番',
                ),
                onSubmitted: _openTable,
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: () => _openTable(_controller.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('確定', style: TextStyle(fontSize: 20)),
                ),
              ),
              const SizedBox(height: 40),
              if (_isLoadingTables)
                const Center(child: CircularProgressIndicator())
              else if (_activeTables.isNotEmpty) ...[
                const Text(
                  '注文中のテーブル',
                  style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const Divider(),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: _activeTables.map((table) {
                    return SizedBox(
                      width: 100,
                      height: 64,
                      child: ElevatedButton(
                        onPressed: () => _openTable(table),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[100],
                          foregroundColor: Colors.orange[900],
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          '卓 $table',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
