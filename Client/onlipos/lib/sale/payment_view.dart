// 決済画面。支払い方法（現金・カード・バーコード・電子マネー）を複数組み合わせて
// 入力し、残金が0になったら会計をサーバーに送信、レシート印刷まで行う。
// 現金払いがある場合はお預かり金入力（CashTenderView）を経由する。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onlipos/api/pos_api_client.dart';
import 'package:onlipos/login/employee_auth_dialog.dart';
import 'package:onlipos/product/catalog_service.dart';
import 'package:onlipos/product/master_sync_api.dart';
import 'package:onlipos/sale/cart_pricing.dart';
import 'package:onlipos/sale/escpos/lan_recipt_api.dart';
import 'package:onlipos/sale/payment_terminal.dart';
import 'package:onlipos/sale/sale_extras_api.dart';
import 'package:onlipos/sale/sale_item.dart';
import 'package:onlipos/sale/send_to_api.dart';

class PaymentView extends StatefulWidget {
  final String operatorName;
  final int operatorId;

  /// 会計するカートの中身。金額は [CartPricing] が計算する
  final List<ScannedItem> items;
  final CartPricing pricing;

  /// 飲食店モード時の卓番など、レシートに追記する情報（例: '卓 3'）
  final String? extraInfo;

  const PaymentView({
    super.key,
    required this.operatorName,
    required this.operatorId,
    required this.items,
    required this.pricing,
    this.extraInfo,
  });

  @override
  State<PaymentView> createState() => _PaymentViewState();
}

enum PaymentMethodType {
  cash(0, '現金', Icons.money),
  card(1, 'カード', Icons.credit_card),
  barcode(2, 'バーコード', Icons.qr_code),
  emoney(3, '電子マネー', Icons.contactless),
  points(4, 'ポイント', Icons.stars),
  voucher(5, '商品券', Icons.confirmation_number),
  houseAccount(6, '掛売', Icons.receipt_long);

  final int value;
  final String label;
  final IconData icon;
  const PaymentMethodType(this.value, this.label, this.icon);

  /// 外部の決済端末で承認を取る手段
  bool get usesTerminal => this == card || this == barcode || this == emoney;
}

class PaymentEntry {
  final PaymentMethodType method;
  final int amount;
  final TerminalResult? terminal;
  PaymentEntry(this.method, this.amount, {this.terminal});
}

/// 客層キー: 東芝テック製レジ等の業務用POSに見られる、性別・年代による
/// 匿名の客層データ収集機能。会計担当が任意で選択し、個人特定はしない。
enum CustomerGenderKey {
  male('male', '男性'),
  female('female', '女性'),
  other('other', 'その他');

  final String value;
  final String label;
  const CustomerGenderKey(this.value, this.label);
}

enum CustomerAgeGroupKey {
  under19('under19', '〜19歳'),
  twenties('twenties', '20代'),
  thirties('thirties', '30代'),
  forties('forties', '40代'),
  fifties('fifties', '50代'),
  sixtyPlus('sixty_plus', '60歳〜');

  final String value;
  final String label;
  const CustomerAgeGroupKey(this.value, this.label);
}

class _PaymentViewState extends State<PaymentView> {
  final List<PaymentEntry> _payments = [];
  final SentToApi _api = SentToApi();
  bool _isProcessing = false;
  CustomerGenderKey? _customerGender;
  CustomerAgeGroupKey? _customerAgeGroup;

  // 会計ごとの冪等キー。送信に失敗して押し直しても同じ値を使い、二重計上を防ぐ
  final String _requestId = SentToApi.newRequestId();
  late CartQuote _quote = widget.pricing.quote(widget.items);
  OrderDiscount? _orderDiscount;
  Map<String, dynamic>? _customer;
  bool _ageVerified = false;

  int get _total => _quote.total;

  void _recalculate() {
    _quote = widget.pricing.quote(widget.items, orderDiscount: _orderDiscount);
    // 合計が変わったら、入力済みの支払いは入れ直す
    _payments.clear();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  int get _paidAmount => _payments.fold(0, (sum, item) => sum + item.amount);
  int get _remainingAmount => _total - _paidAmount;

  // 選択した支払い方法の金額入力ダイアログを開き、残金を上限として支払いを追加する
  Future<void> _addPayment(PaymentMethodType method) async {
    if (_remainingAmount <= 0) return;
    var max = _remainingAmount;
    if (method == PaymentMethodType.points ||
        method == PaymentMethodType.houseAccount) {
      if (_customer == null) {
        return _showError('${method.label}の利用には会員の指定が必要です');
      }
      if (method == PaymentMethodType.points) {
        final used = _payments
            .where((p) => p.method == PaymentMethodType.points)
            .fold(0, (s, p) => s + p.amount);
        final points = (_customer!['points'] as int? ?? 0) - used;
        if (points <= 0) return _showError('利用できるポイントがありません');
        if (points < max) max = points;
      } else if (_customer!['credit_allowed'] != true) {
        return _showError('この会員は掛売を利用できません');
      }
    }

    final amount = await showDialog<int>(
      context: context,
      builder: (context) => _AmountInputDialog(
        title: '${method.label} 金額入力',
        initialAmount: max,
        maxAmount: max,
      ),
    );
    if (amount == null || !mounted) return;

    TerminalResult? terminal;
    if (method.usesTerminal) {
      terminal = await PaymentTerminal.current.pay(
        context,
        methodLabel: method.label,
        amount: amount,
      );
      if (terminal == null || !mounted) return;
    }
    setState(
      () => _payments.add(PaymentEntry(method, amount, terminal: terminal)),
    );
  }

  // 会員を番号・電話番号で検索する
  Future<void> _selectCustomer() async {
    final query = await _askText('会員番号または電話番号');
    if (query == null || query.isEmpty) return;
    final result = await SaleExtrasApi.findCustomer(query);
    final customers = (result['customers'] as List<dynamic>?) ?? [];
    if (!mounted) return;
    if (customers.isEmpty) {
      return _showError(result['message']?.toString() ?? '会員が見つかりません');
    }
    setState(() {
      _customer = customers.first as Map<String, dynamic>;
      _payments.removeWhere(
        (p) =>
            p.method == PaymentMethodType.points ||
            p.method == PaymentMethodType.houseAccount,
      );
    });
  }

  Future<void> _applyCoupon() async {
    final code = await _askText('クーポンコード');
    if (code == null || code.isEmpty) return;
    final base = _quote.subtotal - _quote.promotionDiscount;
    final result = await SaleExtrasApi.checkCoupon(code, base);
    if (!mounted) return;
    final coupon = result['coupon'] as Map<String, dynamic>?;
    if (coupon == null) {
      return _showError(result['message']?.toString() ?? 'クーポンを利用できません');
    }
    setState(() {
      _orderDiscount = OrderDiscount(
        type: coupon['discount_type'] as String,
        value: coupon['discount_value'] as int,
        reason: coupon['name'] as String,
        couponCode: coupon['code'] as String,
      );
      _recalculate();
    });
  }

  // 小計割引（値引き権限者の認証は会計確定時に求める）
  Future<void> _applyOrderDiscount() async {
    final discount = await showDialog<OrderDiscount>(
      context: context,
      builder: (_) => const _OrderDiscountDialog(),
    );
    if (discount == null || !mounted) return;
    final base = _quote.subtotal - _quote.promotionDiscount;
    if (discount.type == 'amount' && discount.value > base) {
      return _showError('割引額が小計を超えています');
    }
    setState(() {
      _orderDiscount = discount;
      _recalculate();
    });
  }

  Future<String?> _askText(String label) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  // 年齢確認・値引き承認。中止された場合は false
  Future<bool> _confirmRequirements() async {
    final age = _quote.requiredAge;
    if (age != null && !_ageVerified) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('年齢確認'),
          content: Text('お客様が$age歳以上であることを確認しましたか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('確認できない'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('確認した'),
            ),
          ],
        ),
      );
      if (ok != true) return false;
      _ageVerified = true;
    }

    if (_quote.needsDiscountApproval && !OperatorApprovals.has('discount')) {
      if (!mounted) return false;
      final approver = await showEmployeeAuthDialog(
        context,
        title: '値引きの承認（値引き権限を持つ担当者）',
        permission: 'discount',
        allowOffline: true,
      );
      if (approver == null) return false;
    }
    return true;
  }

  void _removePayment(int index) {
    setState(() {
      _payments.removeAt(index);
    });
  }

  /// 会計を確定する。現金払いがあればお預かり金入力を挟み、
  /// サーバーへ送信後にレシートを印刷する。
  Future<void> _processPayment() async {
    if (_remainingAmount != 0) return;
    if (!await _confirmRequirements() || !mounted) return;

    // 現金払いがある場合はお預かり金入力へ
    final cashPayment = _payments
        .where((p) => p.method == PaymentMethodType.cash)
        .fold(0, (sum, p) => sum + p.amount);
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
        requestId: _requestId,
        totalAmount: _total,
        receiptNumber: "", // サーバー側で自動生成させるため空文字
        employeeId: widget.operatorId,
        subtotalExTax: _total - _quote.tax,
        taxAmount: _quote.tax,
        details: _quote.details,
        payments: _payments
            .map(
              (p) => {
                'method': p.method.value,
                'amount': p.amount,
                'external_reference': ?p.terminal?.reference,
                'terminal_provider': ?p.terminal?.provider,
              },
            )
            .toList(),
        customerGender: _customerGender?.value,
        customerAgeGroup: _customerAgeGroup?.value,
        customerCode: _customer?['code'] as String?,
        ageVerified: _ageVerified,
        saleOptions: {
          if (_quote.promotionDiscount > 0)
            'promotion_discount_total': _quote.promotionDiscount,
          'coupon_code': ?_orderDiscount?.couponCode,
          if (_orderDiscount != null && _orderDiscount!.couponCode == null) ...{
            'order_discount_type': _orderDiscount!.type,
            'order_discount_value': _orderDiscount!.value,
            'order_discount_reason': _orderDiscount!.reason,
          },
        },
      );
      // 値引きの承認は会計ごとに取り直す
      OperatorApprovals.clear('discount');

      // レシート印刷処理
      try {
        final receiptNo = response['receipt_number'] ?? "UNKNOWN";
        final paymentList = _payments
            .map((p) => {'method': p.method.label, 'amount': p.amount})
            .toList();

        final settings = await CatalogService.instance.settings();
        await ReceiptPrinter().printReceipt(
          receiptNumber: receiptNo,
          totalAmount: _total,
          subtotalExTax: _total - _quote.tax,
          taxAmount: _quote.tax,
          details: _quote.receiptDetails,
          paymentMethods: paymentList,
          change: tenderedCash > 0 ? tenderedCash - cashPayment : 0,
          tenderedCash: tenderedCash,
          extraInfo: widget.extraInfo,
          taxBreakdown: _quote.taxBreakdown,
          discounts: [
            ..._quote.promotions,
            if (_quote.orderDiscount > 0)
              (name: _orderDiscount!.reason, amount: _quote.orderDiscount),
          ],
          receiptUrl: response['receipt_url'] as String?,
          footer: [
            settings['receipt_footer']?.toString() ?? '',
            if (response['points_balance'] != null)
              '今回ポイント ${response['points_earned']} / 残高 ${response['points_balance']}',
          ].where((line) => line.isNotEmpty).join('\n'),
        );
      } catch (e) {
        debugPrint("Printing failed: $e");
      }

      if (mounted) {
        final isOffline = response['offline'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isOffline ? 'オフライン会計として保存しました（後で自動送信）' : '会計が完了しました'),
            backgroundColor: isOffline ? Colors.orange : Colors.green,
          ),
        );
        // 直前の画面（スキャン画面等）に戻り、完了フラグ(true)を渡す
        Navigator.of(context).pop(true);
      }
    } on SaleRejectedException catch (e) {
      if (e.code == 'discount_approval_required') {
        OperatorApprovals.clear('discount');
      }
      if (e.code == 'master_outdated') {
        await _syncMasterAndReturn(e.message);
      } else {
        _showError(e.message);
      }
    } catch (e) {
      _showError('エラー: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // 税率・価格がサーバーと異なる場合: 商品マスタを同期し、カートを新しい価格で作り直してもらう
  Future<void> _syncMasterAndReturn(String message) async {
    try {
      final credentials = await PosApiClient.credentials();
      await ProductSyncService(
        baseUrl: credentials.baseUrl,
        authToken: credentials.token,
      ).syncProducts();
      _showError('$message\n商品マスタを更新しました。商品を登録し直してください。');
      if (mounted) Navigator.of(context).pop('master_updated');
    } catch (_) {
      _showError('$message\n商品マスタの更新に失敗しました。');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('決済 - 担当: ${widget.operatorName}')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 画面幅が狭い場合（スマホ等）は縦スクロールレイアウト
          if (constraints.maxWidth < 900) {
            return SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: 300, child: _buildPaymentList()),
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
              Expanded(flex: 4, child: _buildPaymentList()),
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

  // 左側：これまでに追加された支払い内訳の一覧
  Widget _buildPaymentList() {
    return Container(
      color: Colors.grey[100],
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              '支払い内訳',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _payments.length,
              itemBuilder: (context, index) {
                final payment = _payments[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: ListTile(
                    leading: Icon(payment.method.icon, color: Colors.blue),
                    title: Text(
                      payment.method.label,
                      style: const TextStyle(fontSize: 18),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '¥${payment.amount}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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

  // 右側：合計・支払済・残金の表示と支払い方法ボタン、会計確定ボタン
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
              _buildSummaryRow('合計金額（税込）', _total, isTotal: true),
              const SizedBox(height: 4),
              _buildSummaryRow('税抜小計', _total - _quote.tax, small: true),
              _buildSummaryRow('消費税', _quote.tax, small: true),
              for (final p in _quote.promotions)
                _buildSummaryRow(p.name, -p.amount, small: true),
              if (_quote.orderDiscount > 0)
                _buildSummaryRow(
                  _orderDiscount!.reason,
                  -_quote.orderDiscount,
                  small: true,
                ),
              if (_customer != null)
                Text(
                  '会員: ${_customer!['name'] ?? _customer!['code']}（${_customer!['points']}pt）',
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _selectCustomer,
                    child: const Text('会員'),
                  ),
                  OutlinedButton(
                    onPressed: _applyCoupon,
                    child: const Text('クーポン'),
                  ),
                  OutlinedButton(
                    onPressed: _applyOrderDiscount,
                    child: const Text('小計割引'),
                  ),
                  if (_orderDiscount != null)
                    TextButton(
                      onPressed: () => setState(() {
                        _orderDiscount = null;
                        _recalculate();
                      }),
                      child: const Text('割引を取り消す'),
                    ),
                ],
              ),
              const Divider(height: 32),
              _buildSummaryRow('支払済', _paidAmount),
              const SizedBox(height: 16),
              _buildSummaryRow('残金', _remainingAmount, color: Colors.red),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCustomerSegmentSelector(),
              const SizedBox(height: 24),
              const Text(
                '支払い方法を選択',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
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
                      label: Text(
                        method.label,
                        style: const TextStyle(fontSize: 18),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[50],
                        foregroundColor: Colors.blue[900],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _remainingAmount > 0
                          ? () => _addPayment(method)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 48),
              SizedBox(
                height: 80,
                child: ElevatedButton(
                  onPressed: (_remainingAmount == 0 && !_isProcessing)
                      ? _processPayment
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                  child: _isProcessing
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          '会計確定',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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

  /// 客層キー選択UI（任意）。性別・年代ともタップで選択/解除でき、
  /// 選択しなくても会計は確定できる。
  Widget _buildCustomerSegmentSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '客層キー（任意）',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: CustomerGenderKey.values.map((gender) {
            final selected = _customerGender == gender;
            return ChoiceChip(
              label: Text(gender.label),
              selected: selected,
              onSelected: (_) {
                setState(() {
                  _customerGender = selected ? null : gender;
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: CustomerAgeGroupKey.values.map((ageGroup) {
            final selected = _customerAgeGroup == ageGroup;
            return ChoiceChip(
              label: Text(ageGroup.label),
              selected: selected,
              onSelected: (_) {
                setState(() {
                  _customerAgeGroup = selected ? null : ageGroup;
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  // 「ラベル: 金額」形式の1行を組み立てる共通ウィジェット
  Widget _buildSummaryRow(
    String label,
    int amount, {
    bool isTotal = false,
    bool small = false,
    Color? color,
  }) {
    final labelSize = isTotal
        ? 24.0
        : small
        ? 13.0
        : 20.0;
    final amountSize = isTotal
        ? 40.0
        : small
        ? 15.0
        : 32.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: labelSize,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            color: small ? Colors.grey[600] : null,
          ),
        ),
        Text(
          '¥ $amount',
          style: TextStyle(
            fontSize: amountSize,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            color: small ? Colors.grey[600] : (color ?? Colors.black87),
          ),
        ),
      ],
    );
  }
}

// 小計割引の入力ダイアログ
class _OrderDiscountDialog extends StatefulWidget {
  const _OrderDiscountDialog();

  @override
  State<_OrderDiscountDialog> createState() => _OrderDiscountDialogState();
}

class _OrderDiscountDialogState extends State<_OrderDiscountDialog> {
  final _value = TextEditingController();
  final _reason = TextEditingController();
  String _type = 'amount';

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    final value = int.tryParse(_value.text) ?? 0;
    if (value <= 0 || (_type == 'percent' && value > 100)) return;
    Navigator.of(context).pop(
      OrderDiscount(
        type: _type,
        value: value,
        reason: _reason.text.trim().isEmpty ? '小計割引' : _reason.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('小計割引'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'amount', label: Text('金額')),
              ButtonSegment(value: 'percent', label: Text('%')),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() => _type = v.first),
          ),
          TextField(
            controller: _value,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: _type == 'amount' ? '割引額（円）' : '割引率（%）',
            ),
          ),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: '理由'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(onPressed: _confirm, child: const Text('適用')),
      ],
    );
  }
}

// 金額入力ダイアログ
class _AmountInputDialog extends StatefulWidget {
  final String title;
  final int initialAmount;
  final int maxAmount;

  const _AmountInputDialog({
    required this.title,
    required this.initialAmount,
    required this.maxAmount,
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
      Navigator.of(context).pop(amount);
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(onPressed: _confirm, child: const Text('確定')),
      ],
    );
  }
}

// お預かり金入力画面
class CashTenderView extends StatefulWidget {
  final int totalCashAmount;
  final String operatorName;

  const CashTenderView({
    super.key,
    required this.totalCashAmount,
    required this.operatorName,
  });

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
      body: SingleChildScrollView(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '現金支払額: ¥${widget.totalCashAmount}',
                  style: const TextStyle(fontSize: 24),
                  textAlign: TextAlign.center,
                ),
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
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'お釣り: ¥${_change >= 0 ? _change : '-'}',
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
                    onPressed: _canFinish
                        ? () => Navigator.of(context).pop(_tender)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('会計完了', style: TextStyle(fontSize: 24)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
