import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onlipos/sale/send_to_api.dart';
import 'package:onlipos/sale/escpos/lan_recipt_api.dart';

class PaymentView extends StatefulWidget {
  final String operatorName;
  final int totalAmount;
  final List<Map<String, dynamic>> saleDetails;

  const PaymentView({
    super.key,
    required this.operatorName,
    required this.totalAmount,
    required this.saleDetails,
  });

  @override
  State<PaymentView> createState() => _PaymentViewState();
}

enum PaymentMethodType {
  cash(0, '現金', Icons.money),
  card(1, 'カード', Icons.credit_card),
  barcode(2, 'バーコード', Icons.qr_code);

  final int value;
  final String label;
  final IconData icon;
  const PaymentMethodType(this.value, this.label, this.icon);
}

class PaymentEntry {
  final PaymentMethodType method;
  final int amount;
  PaymentEntry(this.method, this.amount);
}

class _PaymentViewState extends State<PaymentView> {
  final List<PaymentEntry> _payments = [];
  final SentToApi _api = SentToApi();
  bool _isProcessing = false;

  int get _paidAmount => _payments.fold(0, (sum, item) => sum + item.amount);
  int get _remainingAmount => widget.totalAmount - _paidAmount;

  void _addPayment(PaymentMethodType method) {
    if (_remainingAmount <= 0) return;

    showDialog(
      context: context,
      builder: (context) => _AmountInputDialog(
        title: '${method.label} 金額入力',
        initialAmount: _remainingAmount,
        maxAmount: _remainingAmount,
        onConfirmed: (amount) {
          setState(() {
            _payments.add(PaymentEntry(method, amount));
          });
        },
      ),
    );
  }

  void _removePayment(int index) {
    setState(() {
      _payments.removeAt(index);
    });
  }

  Future<void> _processPayment() async {
    if (_remainingAmount != 0) return;

    // 現金払いがある場合はお預かり金入力へ
    final cashPayment = _payments.where((p) => p.method == PaymentMethodType.cash).fold(0, (sum, p) => sum + p.amount);
    int tenderedCash = 0;
    
    if (cashPayment > 0) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CashTenderView(
            totalCashAmount: cashPayment,
            operatorName: widget.operatorName,
          ),
        ),
      );
      
      // お預かり金入力がキャンセルされた場合
      if (result == null) return;
      tenderedCash = result as int;
    }

    // API送信処理
    setState(() => _isProcessing = true);
    try {
      final response = await _api.sendSale(
        totalAmount: widget.totalAmount,
        receiptNumber: "", // サーバー側で自動生成させるため空文字
        details: widget.saleDetails,
        payments: _payments
            .map((p) => {
                  'method': p.method.value,
                  'amount': p.amount,
                })
            .toList(),
      );

      // レシート印刷処理
      try {
        final receiptNo = response['receipt_number'] ?? "UNKNOWN";
        final paymentList = _payments.map((p) => {
          'method': p.method.label,
          'amount': p.amount,
        }).toList();

        await ReceiptPrinter().printReceipt(
          receiptNumber: receiptNo,
          totalAmount: widget.totalAmount,
          details: widget.saleDetails,
          paymentMethods: paymentList,
          change: tenderedCash > 0 ? tenderedCash - cashPayment : 0,
          tenderedCash: tenderedCash,
        );
      } catch (e) {
        print("Printing failed: $e");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('会計が完了しました'), backgroundColor: Colors.green),
        );
        // 直前の画面（スキャン画面等）に戻り、完了フラグ(true)を渡す
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: '), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('決済 - 担当: ${widget.operatorName}'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 画面幅が狭い場合（スマホ等）は縦スクロールレイアウト
          if (constraints.maxWidth < 900) {
            return SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(
                    height: 300,
                    child: _buildPaymentList(),
                  ),
                  const Divider(height: 1),
                  Container(
                    color: Colors.white,
                    child: _buildPaymentControls(null),
                  ),
                ],
              ),
            );
          }
          // PC/タブレット向け横分割レイアウト
          return Row(
            children: [
              Expanded(
                flex: 4,
                child: _buildPaymentList(),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 3,
                child: Container(
                  color: Colors.white,
                  child: LayoutBuilder(
                    builder: (context, rightConstraints) {
                      return _buildPaymentControls(rightConstraints);
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPaymentList() {
    return Container(
      color: Colors.grey[100],
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('支払い内訳', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _payments.length,
              itemBuilder: (context, index) {
                final payment = _payments[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: Icon(payment.method.icon, color: Colors.blue),
                    title: Text(payment.method.label, style: const TextStyle(fontSize: 18)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('¥${payment.amount}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _removePayment(index),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentControls(BoxConstraints? constraints) {
    Widget content = Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSummaryRow('合計金額', widget.totalAmount, isTotal: true),
              const Divider(height: 32),
              _buildSummaryRow('支払済', _paidAmount),
              const SizedBox(height: 16),
              _buildSummaryRow('残金', _remainingAmount, color: Colors.red),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Text('支払い方法を選択', style: TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: PaymentMethodType.values.map((method) {
                  return SizedBox(
                    width: 140,
                    height: 80,
                    child: ElevatedButton.icon(
                      icon: Icon(method.icon, size: 32),
                      label: Text(method.label, style: const TextStyle(fontSize: 18)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[50],
                        foregroundColor: Colors.blue[900],
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _remainingAmount > 0 ? () => _addPayment(method) : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 48),
              SizedBox(
                height: 80,
                child: ElevatedButton(
                  onPressed: (_remainingAmount == 0 && !_isProcessing) ? _processPayment : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                  child: _isProcessing
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('会計確定', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (constraints != null) {
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: content),
        ),
      );
    }
    return content;
  }

  Widget _buildSummaryRow(String label, int amount, {bool isTotal = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: isTotal ? 24 : 20, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
        Text(
          '¥ $amount',
          style: TextStyle(
            fontSize: isTotal ? 40 : 32,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.black87,
          ),
        ),
      ],
    );
  }
}

// 金額入力ダイアログ
class _AmountInputDialog extends StatefulWidget {
  final String title;
  final int initialAmount;
  final int maxAmount;
  final Function(int) onConfirmed;

  const _AmountInputDialog({
    required this.title,
    required this.initialAmount,
    required this.maxAmount,
    required this.onConfirmed,
  });

  @override
  State<_AmountInputDialog> createState() => _AmountInputDialogState();
}

class _AmountInputDialogState extends State<_AmountInputDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialAmount.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final amount = int.tryParse(_controller.text);
    if (amount != null && amount > 0 && amount <= widget.maxAmount) {
      widget.onConfirmed(amount);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        autofocus: true,
        decoration: const InputDecoration(
          prefixText: '¥ ',
          border: OutlineInputBorder(),
          labelText: '支払い金額',
        ),
        style: const TextStyle(fontSize: 32),
        onSubmitted: (_) => _confirm(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
        ElevatedButton(onPressed: _confirm, child: const Text('確定')),
      ],
    );
  }
}

// お預かり金入力画面
class CashTenderView extends StatefulWidget {
  final int totalCashAmount;
  final String operatorName;

  const CashTenderView({super.key, required this.totalCashAmount, required this.operatorName});

  @override
  State<CashTenderView> createState() => _CashTenderViewState();
}

class _CashTenderViewState extends State<CashTenderView> {
  final TextEditingController _controller = TextEditingController();
  int _change = 0;
  int _tender = 0;
  bool _canFinish = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_calculateChange);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _calculateChange() {
    _tender = int.tryParse(_controller.text) ?? 0;
    setState(() {
      _change = _tender - widget.totalCashAmount;
      _canFinish = _change >= 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('お預かり金入力 - 担当: ${widget.operatorName}')),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('現金支払額: ¥${widget.totalCashAmount}', style: const TextStyle(fontSize: 24), textAlign: TextAlign.center),
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autofocus: true,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: 'お預かり金',
                  prefixText: '¥ ',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              Text(
                'お釣り: ¥${_change >= 0 ? _change : '-' }',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: _change >= 0 ? Colors.blue : Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              SizedBox(
                height: 64,
                child: ElevatedButton(
                  onPressed: _canFinish ? () => Navigator.of(context).pop(_tender) : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  child: const Text('会計完了', style: TextStyle(fontSize: 24)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
