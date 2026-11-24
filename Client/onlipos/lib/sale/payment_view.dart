// 決済画面。支払い方法（現金・カード・バーコード・電子マネー）を複数組み合わせて
// 入力し、残金が0になったら会計をサーバーに送信、レシート印刷まで行う。
// 現金払いがある場合はお預かり金入力（CashTenderView）を経由する。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:onlipos/ui/app_session.dart';
import 'package:onlipos/ui/num_pad.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:onlipos/ui/amount_dialog.dart';
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
    showMessage(context, message, MessageType.error);
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

    final amount = await showAmountDialog(
      context,
      title: '${method.label}で支払う金額',
      initial: max,
      max: max,
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

  // お釣りを大きく表示する
  Future<void> _showChange(int tendered, int change) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('会計が完了しました', textAlign: TextAlign.center),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('お釣り', style: TextStyle(fontSize: 20)),
            FittedBox(
              child: Text(
                yen(change),
                style: const TextStyle(
                  fontSize: 68,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
            Text(
              'お預かり ${yen(tendered)}　合計 ${yen(_total)}',
              style: const TextStyle(color: AppColors.secondary),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        SizedBox(
          width: 260,
          child: ElevatedButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('次のお客様へ'),
          ),
        ),
      ],
    ),
  );

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
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('やめる'),
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
            OutlinedButton(
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
        title: '値引きの確認（値引きできる人）',
        permission: 'discount',
        allowOffline: true,
      );
      if (approver == null) return false;
    }
    return true;
  }

  // 残りをすべて現金で支払い、そのままお預かり金の入力へ進む
  Future<void> _payAllCash() async {
    if (_remainingAmount > 0) {
      setState(
        () => _payments.add(
          PaymentEntry(PaymentMethodType.cash, _remainingAmount),
        ),
      );
    }
    await _processPayment();
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

      // レシートの印刷。プリンターの応答を待たずに、お釣りの表示へ進む
      try {
        final receiptNo = response['receipt_number'] ?? "UNKNOWN";
        final paymentList = _payments
            .map((p) => {'method': p.method.label, 'amount': p.amount})
            .toList();

        final settings = await CatalogService.instance.settings();
        final printing = ReceiptPrinter().printReceipt(
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
        unawaited(
          printing.catchError((Object e) => debugPrint('Printing failed: $e')),
        );
      } catch (e) {
        debugPrint("Printing failed: $e");
      }

      if (mounted) {
        final isOffline = response['offline'] == true;
        AppSession.instance.refreshCounts();
        final change = tenderedCash > 0 ? tenderedCash - cashPayment : 0;
        if (change > 0) {
          await _showChange(tenderedCash, change);
          if (!mounted) return;
        }
        showMessage(
          context,
          isOffline ? '会計を端末に保存しました（通信できるようになると自動で送信します）' : '会計が完了しました',
          isOffline ? MessageType.warning : MessageType.success,
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
    return PopScope(
      canPop: _payments.isEmpty && !_isProcessing,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _isProcessing) return;
        final navigator = Navigator.of(context);
        final ok = await confirm(
          context,
          title: '前の画面に戻りますか？',
          message: '入力した支払いは取り消されます。カードなどの決済が済んでいる場合は、決済端末でも取り消してください。',
          okLabel: '戻る',
          cancelLabel: '会計を続ける',
          danger: true,
        );
        if (ok) navigator.pop();
      },
      child: Scaffold(
        appBar: AppHeader('お支払い', subtitle: '担当: ${widget.operatorName}'),
        body: LayoutBuilder(
          builder: (context, constraints) {
            // 画面幅が狭い場合（スマホ等）は縦スクロールレイアウト
            if (constraints.maxWidth < 760) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTotals(),
                    const SizedBox(height: 12),
                    _buildMethods(),
                    const SizedBox(height: 12),
                    _buildConfirm(),
                  ],
                ),
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                    child: _buildTotals(),
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                          child: _buildMethods(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 16, 16),
                        child: _buildConfirm(),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // 左側: 合計・割引・会員・これまでの支払い
  Widget _buildTotals() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '合計（税込）',
                style: TextStyle(fontSize: 17, color: AppColors.secondary),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  yen(_total),
                  style: const TextStyle(
                    fontSize: 52,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              LabelValue('税抜', yen(_total - _quote.tax)),
              LabelValue('消費税', yen(_quote.tax)),
              for (final p in _quote.promotions)
                LabelValue(p.name, yen(-p.amount), color: AppColors.danger),
              if (_quote.orderDiscount > 0)
                LabelValue(
                  _orderDiscount!.reason,
                  yen(-_quote.orderDiscount),
                  color: AppColors.danger,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_customer != null)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.person, color: AppColors.primary),
                  title: Text('${_customer!['name'] ?? _customer!['code']} 様'),
                  subtitle: Text('ポイント ${_customer!['points']}'),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _optionButton(
                    Icons.card_membership,
                    _customer == null ? '会員' : '会員を変える',
                    _selectCustomer,
                  ),
                  _optionButton(
                    Icons.confirmation_number_outlined,
                    'クーポン',
                    _applyCoupon,
                  ),
                  _optionButton(Icons.percent, '合計から割引', _applyOrderDiscount),
                  if (_orderDiscount != null)
                    TextButton(
                      onPressed: () => setState(() {
                        _orderDiscount = null;
                        _recalculate();
                      }),
                      child: const Text('割引をやめる'),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (_payments.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: '入力した支払い',
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                for (final (index, payment) in _payments.indexed)
                  Row(
                    children: [
                      Icon(payment.method.icon, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          payment.method.label,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                      Text(
                        yen(payment.amount),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        tooltip: 'この支払いを取り消す',
                        icon: const Icon(
                          Icons.delete_outline,
                          color: AppColors.danger,
                        ),
                        onPressed: _isProcessing
                            ? null
                            : () => _removePayment(index),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _optionButton(IconData icon, String label, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: _isProcessing ? null : onTap,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      );

  // 右側: 残りの金額と支払い方法
  Widget _buildMethods() {
    final remaining = _remainingAmount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: remaining > 0
                ? AppColors.warningSoft
                : AppColors.successSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  remaining > 0
                      ? (_payments.isEmpty ? 'お支払い方法を選んでください' : 'あと')
                      : '支払いの入力が終わりました',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (remaining > 0)
                Text(
                  yen(remaining),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.warning,
                  ),
                )
              else
                const Icon(Icons.check_circle, color: AppColors.success),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (remaining > 0) ...[
          SizedBox(
            height: 72,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _payAllCash,
              icon: const Icon(Icons.payments, size: 28),
              label: Text(
                _payments.isEmpty ? '現金でお会計' : '残りを現金でお会計',
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
          const SizedBox(height: 10),
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisExtent: 64,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            children: [
              for (final method in PaymentMethodType.values)
                OutlinedButton.icon(
                  onPressed: _isProcessing ? null : () => _addPayment(method),
                  icon: Icon(method.icon),
                  label: Text(
                    method == PaymentMethodType.cash ? '現金（一部）' : method.label,
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _buildCustomerSegmentSelector(),
      ],
    );
  }

  Widget _buildConfirm() {
    return SizedBox(
      width: double.infinity,
      height: 76,
      child: ElevatedButton.icon(
        onPressed: (_remainingAmount == 0 && !_isProcessing)
            ? _processPayment
            : null,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
        icon: _isProcessing
            ? const SizedBox.square(
                dimension: 26,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : const Icon(Icons.check_circle, size: 30),
        label: Text(
          _isProcessing ? '送信しています…' : '会計を確定する',
          style: const TextStyle(fontSize: 26),
        ),
      ),
    );
  }

  /// 客層の選択（任意）。性別・年代ともタップで選択/解除でき、選択しなくても会計は確定できる。
  Widget _buildCustomerSegmentSelector() {
    Widget chips<T>(
      Iterable<(T, String)> values,
      T? selected,
      void Function(T? value) onSelected,
    ) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (value, label) in values)
          ChoiceChip(
            label: Text(label),
            selected: selected == value,
            onSelected: (on) => setState(() => onSelected(on ? value : null)),
          ),
      ],
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        leading: const Icon(Icons.groups_outlined),
        title: const Text(
          'お客様の層（入力しなくてもかまいません）',
          style: TextStyle(fontSize: 15),
        ),
        subtitle: (_customerGender ?? _customerAgeGroup) == null
            ? null
            : Text(
                [?_customerGender?.label, ?_customerAgeGroup?.label].join('・'),
              ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          chips(
            CustomerGenderKey.values.map((g) => (g, g.label)),
            _customerGender,
            (v) => _customerGender = v,
          ),
          const SizedBox(height: 8),
          chips(
            CustomerAgeGroupKey.values.map((a) => (a, a.label)),
            _customerAgeGroup,
            (v) => _customerAgeGroup = v,
          ),
        ],
      ),
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
      title: const Text('合計から割引'),
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
          const SizedBox(height: 14),
          TextField(
            controller: _value,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: _type == 'amount' ? '割引額（円）' : '割引率（%）',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: '理由（なくても可）'),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('やめる'),
        ),
        ElevatedButton(onPressed: _confirm, child: const Text('割引する')),
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

  // ちょうど・切りのよいお札の金額を候補として出す
  List<int> get _suggestions {
    final total = widget.totalCashAmount;
    final amounts = <int>{
      total,
      for (final unit in [1000, 5000, 10000]) (total / unit).ceil() * unit,
    }.toList()..sort();
    return amounts;
  }

  void _set(int amount) {
    final text = '$amount';
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _finish() {
    if (_canFinish) Navigator.of(context).pop(_tender);
  }

  @override
  Widget build(BuildContext context) {
    final amounts = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LabelValue(
          'お支払い（現金）',
          yen(widget.totalCashAmount),
          size: 30,
          bold: true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          keyboardType: TextInputType.none,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(
            labelText: 'お預かり',
            prefixText: '¥ ',
          ),
          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
          onSubmitted: (_) => _finish(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final amount in _suggestions)
              OutlinedButton(
                onPressed: () => _set(amount),
                child: Text(
                  amount == widget.totalCashAmount ? 'ちょうど' : yen(amount),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: _canFinish ? AppColors.primarySoft : const Color(0xFFEEF1F6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: LabelValue(
            _tender > 0 && !_canFinish ? 'あと' : 'お釣り',
            _tender == 0 ? '-' : yen(_change.abs()),
            size: 38,
            bold: true,
            color: _tender > 0 && !_canFinish
                ? AppColors.danger
                : AppColors.primary,
          ),
        ),
      ],
    );
    final finish = SizedBox(
      height: 72,
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _canFinish ? _finish : null,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
        icon: const Icon(Icons.check_circle, size: 28),
        label: const Text('会計を完了する', style: TextStyle(fontSize: 24)),
      ),
    );
    return Scaffold(
      appBar: AppHeader('お預かり', subtitle: '担当: ${widget.operatorName}'),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: LayoutBuilder(
              builder: (context, box) {
                final pad = NumPad(
                  controller: _controller,
                  showDoubleZero: true,
                  maxLength: 8,
                );
                if (box.maxWidth < 640) {
                  return Column(
                    children: [
                      SectionCard(child: amounts),
                      const SizedBox(height: 12),
                      pad,
                      const SizedBox(height: 12),
                      finish,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: SectionCard(child: amounts)),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 320,
                      child: Column(
                        children: [pad, const SizedBox(height: 12), finish],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
