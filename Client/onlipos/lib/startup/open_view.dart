import 'package:flutter/material.dart';
import 'open_api.dart';
import '../menu/menu_top_view.dart';
import '../sale/escpos/lan_recipt_api.dart';

class OpenView extends StatefulWidget {
  final int employeeId;
  final String employeeName;
  final DateTime openDate;

  const OpenView({
    super.key,
    required this.employeeId,
    required this.employeeName,
    required this.openDate,
  });

  @override
  State<OpenView> createState() => _OpenViewState();
}

class _OpenViewState extends State<OpenView> {
  // 金種リスト
  final List<int> _denominations = [10000, 5000, 1000, 500, 100, 50, 10, 5, 1];
  
  // 各金種の枚数を管理するコントローラーのマップ
  final Map<int, TextEditingController> _controllers = {};
  
  int _totalAmount = 0;
  bool _isLoading = false;
  final OpenApi _openApi = OpenApi();

  @override
  void initState() {
    super.initState();
    // コントローラーの初期化とリスナー設定
    for (var denomination in _denominations) {
      var controller = TextEditingController(text: '');
      controller.addListener(_calculateTotal);
      _controllers[denomination] = controller;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ReceiptPrinter.openDrawer();
    });
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _calculateTotal() {
    int total = 0;
    _controllers.forEach((denomination, controller) {
      int count = int.tryParse(controller.text) ?? 0;
      total += denomination * count;
    });

    if (mounted) {
      setState(() {
        _totalAmount = total;
      });
    }
  }

  Future<void> _handleOpenStore() async {
    setState(() {
      _isLoading = true;
    });

    // 金種ごとの枚数マップを作成
    Map<int, int> cashDrawer = {};
    _controllers.forEach((denomination, controller) {
      cashDrawer[denomination] = int.tryParse(controller.text) ?? 0;
    });

    final dateStr = "${widget.openDate.year}-${widget.openDate.month.toString().padLeft(2, '0')}-${widget.openDate.day.toString().padLeft(2, '0')}";

    final result = await _openApi.openStore(
      employeeId: widget.employeeId,
      openDate: dateStr,
      cashDrawer: cashDrawer,
      totalAmount: _totalAmount,
    );

    setState(() {
      _isLoading = false;
    });

    if (result['success'] == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('開設処理が完了しました')),
      );
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MenuTopView(
            employeeId: widget.employeeId,
            employeeName: widget.employeeName,
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'エラーが発生しました')),
      );
    }
  }

  String _formatCurrency(int number) {
    return number.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = "${widget.openDate.year}年${widget.openDate.month}月${widget.openDate.day}日";

    return PopScope(
      canPop: false,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('レジ開設処理'),
        automaticallyImplyLeading: false, // 戻るボタンを非表示（ログアウト処理が必要なため）
      ),
      body: Row(
        children: [
          // 左側：情報パネル
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey[100],
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('開設日: $dateStr', style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 10),
                  Text('担当者: ${widget.employeeName}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Divider(height: 40),
                  const Text('釣銭準備金 合計', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  Text(
                    '¥${_formatCurrency(_totalAmount)}',
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleOpenStore,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('開設する', style: TextStyle(fontSize: 20)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 右側：金種入力フォーム
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text('金種別枚数入力', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  ..._denominations.map((denomination) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(
                              '¥${_formatCurrency(denomination)}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: TextField(
                              controller: _controllers[denomination],
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.right,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                suffixText: '枚',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}