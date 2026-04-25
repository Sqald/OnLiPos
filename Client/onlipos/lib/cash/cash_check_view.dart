import 'package:flutter/material.dart';

import 'cash_log_api.dart';
import '../sale/escpos/lan_recipt_api.dart';

class CashCheckView extends StatefulWidget {
  final int employeeId;
  final String employeeName;

  const CashCheckView({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<CashCheckView> createState() => _CashCheckViewState();
}

class _CashCheckViewState extends State<CashCheckView> {
  final List<int> _denominations = [10000, 5000, 1000, 500, 100, 50, 10, 5, 1];
  final Map<int, TextEditingController> _controllers = {};

  int _totalAmount = 0;
  int? _lastAmount;
  int? _expectedAmount;
  int? _diffAmount;
  DateTime? _lastLoggedAt;
  bool _isLoading = false;
  final CashLogApi _api = CashLogApi();

  @override
  void initState() {
    super.initState();
    for (final denomination in _denominations) {
      final controller = TextEditingController(text: '');
      controller.addListener(_calculateTotal);
      _controllers[denomination] = controller;
    }
    _loadContext();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ReceiptPrinter.openDrawer();
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _calculateTotal() {
    var total = 0;
    _controllers.forEach((denomination, controller) {
      final count = int.tryParse(controller.text) ?? 0;
      total += denomination * count;
    });

    if (!mounted) return;
    setState(() {
      _totalAmount = total;
      if (_expectedAmount != null) {
        _diffAmount = _totalAmount - (_expectedAmount ?? 0);
      }
    });
  }

  Future<void> _loadContext() async {
    final result = await _api.fetchCashCheckContext();

    if (!mounted) return;

    setState(() {
      if (result['success'] == true) {
        _lastAmount = result['last_amount'] is int
            ? result['last_amount'] as int
            : int.tryParse(result['last_amount']?.toString() ?? '');
        _expectedAmount = result['expected_amount'] is int
            ? result['expected_amount'] as int
            : int.tryParse(result['expected_amount']?.toString() ?? '');
        if (_expectedAmount != null) {
          _diffAmount = _totalAmount - _expectedAmount!;
        }
        if (result['last_logged_at'] != null) {
          _lastLoggedAt = DateTime.tryParse(result['last_logged_at'].toString());
        }
      }
    });
  }

  Future<void> _submit() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    final cashDrawer = <int, int>{};
    _controllers.forEach((denomination, controller) {
      cashDrawer[denomination] = int.tryParse(controller.text) ?? 0;
    });

    final result = await _api.cashCheck(
      employeeId: widget.employeeId,
      cashDrawer: cashDrawer,
      totalAmount: _totalAmount,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        // サーバー側を真実としつつ、営業日トータル差異の考え方は維持する。
        _lastAmount = result['last_amount'] is int
            ? result['last_amount'] as int
            : int.tryParse(result['last_amount']?.toString() ?? '');
        _expectedAmount = result['expected_amount'] is int
            ? result['expected_amount'] as int
            : int.tryParse(result['expected_amount']?.toString() ?? '');
        if (_expectedAmount != null) {
          _diffAmount = _totalAmount - _expectedAmount!;
        }
        if (result['last_logged_at'] != null) {
          _lastLoggedAt = DateTime.tryParse(result['last_logged_at'].toString());
        }
      }
    });

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('レジ金チェックを登録しました')),
      );
    } else {
      final message = result['message']?.toString() ?? 'エラーが発生しました';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  String _formatCurrency(int number) {
    return number.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }

  Widget _buildDenominationInputs() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text(
            '金種別枚数入力',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
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
    );
  }

  Widget _buildSummarySection({bool compact = false}) {
    return Container(
      color: Colors.grey[100],
      padding: EdgeInsets.all(compact ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '担当者: ${widget.employeeName}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: compact ? 8 : 24),
          const Text('レジ内現金 合計', style: TextStyle(fontSize: 16, color: Colors.grey)),
          Text(
            '¥${_formatCurrency(_totalAmount)}',
            style: TextStyle(
              fontSize: compact ? 32 : 40,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          if (_lastAmount != null || _expectedAmount != null || _diffAmount != null)
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('チェック結果',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    if (_lastLoggedAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0, bottom: 6.0),
                        child: Text('前回チェック: ${_lastLoggedAt!.toLocal()}',
                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ),
                    if (_lastAmount != null) _buildResultRow('前回レジ金', _lastAmount!),
                    if (_expectedAmount != null) _buildResultRow('想定レジ金', _expectedAmount!),
                    _buildResultRow('今回レジ金', _totalAmount),
                    if (_diffAmount != null)
                      _buildResultRow('差異', _diffAmount!, highlight: _diffAmount != 0),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('レジ金チェック')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 幅 600px 未満はスマホ向け縦レイアウト
          if (constraints.maxWidth < 600) {
            return Column(
              children: [
                _buildSummarySection(compact: true),
                Expanded(child: _buildDenominationInputs()),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('チェック結果を登録', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          // 幅 600px 以上はタブレット/デスクトップ向け横レイアウト
          return Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  color: Colors.grey[100],
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('担当者: ${widget.employeeName}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 24),
                      const Text('レジ内現金 合計',
                          style: TextStyle(fontSize: 16, color: Colors.grey)),
                      Text('¥${_formatCurrency(_totalAmount)}',
                          style: const TextStyle(
                              fontSize: 40, fontWeight: FontWeight.bold, color: Colors.blue)),
                      const SizedBox(height: 24),
                      if (_lastAmount != null || _expectedAmount != null || _diffAmount != null)
                        Card(
                          margin: const EdgeInsets.only(top: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('チェック結果',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                if (_lastLoggedAt != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                                    child: Text('前回チェック: ${_lastLoggedAt!.toLocal()}',
                                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  ),
                                if (_lastAmount != null) _buildResultRow('前回レジ金', _lastAmount!),
                                if (_expectedAmount != null)
                                  _buildResultRow('想定レジ金', _expectedAmount!),
                                _buildResultRow('今回レジ金', _totalAmount),
                                if (_diffAmount != null)
                                  _buildResultRow('差異', _diffAmount!, highlight: _diffAmount != 0),
                              ],
                            ),
                          ),
                        ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text('チェック結果を登録', style: TextStyle(fontSize: 20)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(flex: 3, child: _buildDenominationInputs()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildResultRow(String label, int amount, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            '¥${_formatCurrency(amount)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: highlight ? Colors.red : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

