import 'package:flutter/material.dart';

import '../login/login_top_view.dart';
import '../sale/escpos/lan_recipt_api.dart';
import 'cash_log_api.dart';

class CashCloseView extends StatefulWidget {
  final int employeeId;
  final String employeeName;

  const CashCloseView({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<CashCloseView> createState() => _CashCloseViewState();
}

class _CashCloseViewState extends State<CashCloseView> {
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

    final result = await _api.closeRegister(
      employeeId: widget.employeeId,
      cashDrawer: cashDrawer,
      totalAmount: _totalAmount,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
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

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('レジ精算を登録しました')),
      );
      // 精算完了後はセッションを終了し、ログイン画面へ戻す
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginTopView()),
        (route) => false,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('レジ精算'),
      ),
      body: Row(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey[100],
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '担当者: ${widget.employeeName}',
                    style:
                        const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'レジ内現金 合計（締め）',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  Text(
                    '¥${_formatCurrency(_totalAmount)}',
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_lastAmount != null || _expectedAmount != null || _diffAmount != null)
                    Card(
                      margin: const EdgeInsets.only(top: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '精算前の状況',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            if (_lastLoggedAt != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                                child: Text(
                                  '前回チェック: ${_lastLoggedAt!.toLocal()}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ),
                            if (_lastAmount != null)
                              _buildResultRow('前回レジ金', _lastAmount!),
                            if (_expectedAmount != null)
                              _buildResultRow('想定レジ金', _expectedAmount!),
                            _buildResultRow('今回レジ金（締め）', _totalAmount),
                            if (_diffAmount != null)
                              _buildResultRow(
                                '差異',
                                _diffAmount!,
                                highlight: _diffAmount != 0,
                              ),
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
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('精算を確定', style: TextStyle(fontSize: 20)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
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
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
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
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

