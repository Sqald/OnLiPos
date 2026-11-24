/// 返品・返金処理画面。不正防止のため従業員2名の認証を必須とし、
/// レシート番号(手入力またはQR読み取り)で対象の会計を検索、
/// 商品ごとに返品数量を指定してサーバーへ登録・返品レシートを印字する。
library;

import 'package:material_ui/material_ui.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:onlipos/sale/cart_panel.dart';
import 'package:onlipos/login/employee_auth_dialog.dart';
import 'package:onlipos/api/pos_api_client.dart';
import 'package:onlipos/refund/refund_api.dart';
import 'package:onlipos/refund/qr_scan_receipt_view.dart';
import 'package:onlipos/sale/escpos/lan_recipt_api.dart';

class ReturnRefundView extends StatefulWidget {
  final String operatorName;
  final int operatorId;

  const ReturnRefundView({
    super.key,
    this.operatorName = '担当者',
    this.operatorId = 0,
  });

  @override
  State<ReturnRefundView> createState() => _ReturnRefundViewState();
}

class _ReturnRefundViewState extends State<ReturnRefundView> {
  // 従業員認証（2名）
  final List<int?> _employeeIds = [null, null];
  final List<String?> _employeeNames = [null, null];

  final TextEditingController _receiptNumberController =
      TextEditingController();
  bool _saleLoading = false;
  Map<String, dynamic>? _saleData;

  // 返品する数量（saledetail id -> quantity to return）
  final Map<int, int> _returnQuantities = {};
  bool _submitLoading = false;

  @override
  void dispose() {
    _receiptNumberController.dispose();
    super.dispose();
  }

  bool get _twoAuthenticated =>
      _employeeIds[0] != null && _employeeIds[1] != null;

  // 返品できる担当者を1人確認する（権限はサーバーで確認。同じ人は2回使えない）
  Future<void> _authenticate(int index) async {
    final operator = await showEmployeeAuthDialog(
      context,
      title: '返品の確認（${index + 1}人目）',
      permission: 'refund',
    );
    if (operator == null || !mounted) return;
    if (_employeeIds[1 - index] == operator.id) {
      showMessage(context, '2人目は、別の人が確認してください', MessageType.error);
      return;
    }
    setState(() {
      _employeeIds[index] = operator.id;
      _employeeNames[index] = operator.name;
    });
  }

  // QRスキャン画面を開き、読み取ったレシート番号を入力欄に反映する
  Future<void> _openQrScanner() async {
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanReceiptView()),
    );
    if (value != null && mounted) {
      _receiptNumberController.text = value;
    }
  }

  // レシート番号で対象の売上を検索する。返品済みの場合は処理を中断する
  Future<void> _loadSale() async {
    final receipt = _receiptNumberController.text.trim();
    if (receipt.isEmpty) {
      showMessage(context, 'レシート番号を入力するかQRで読み取ってください', MessageType.error);
      return;
    }
    setState(() {
      _saleLoading = true;
      _saleData = null;
      _returnQuantities.clear();
    });
    final result = await RefundApi.getSaleByReceipt(receipt);
    if (!mounted) return;
    setState(() => _saleLoading = false);
    if (result['success'] == true && result['details'] != null) {
      final sale = result['sale'] as Map<String, dynamic>?;
      final alreadyRefunded = sale?['refunded'] == true;
      if (sale?['voided'] == true) {
        showMessage(context, 'この会計は取消済みのため返品できません', MessageType.error);
        return;
      }
      if (alreadyRefunded) {
        if (mounted) {
          showMessage(context, 'この会計はすでに返品済みです', MessageType.error);
        }
        return;
      }
      setState(() {
        _saleData = result;
        final details = result['details'] as List<dynamic>;
        for (final d in details) {
          final id = (d as Map)['id'] as int?;
          if (id != null) _returnQuantities[id] = 0;
        }
      });
    } else {
      showMessage(
        context,
        result['message']?.toString() ?? '会計を取得できませんでした',
        MessageType.error,
      );
    }
  }

  // 数量に応じた返金額（サーバーが支払額から計算した値。1個, 2個, …の順）
  int _refundAmount(Map<dynamic, dynamic> detail, int quantity) {
    if (quantity <= 0) return 0;
    final amounts = detail['refund_amounts'] as List<dynamic>?;
    if (amounts != null && quantity <= amounts.length) {
      return (amounts[quantity - 1] as num).toInt();
    }
    return ((detail['unit_price'] as num?)?.toInt() ?? 0) * quantity;
  }

  // 指定された返品数量から返金合計額を計算する
  int get _totalRefundAmount {
    if (_saleData == null || _saleData!['details'] == null) return 0;
    int total = 0;
    for (final d in _saleData!['details'] as List<dynamic>) {
      final m = d as Map;
      final id = m['id'] as int?;
      final qty = id != null ? (_returnQuantities[id] ?? 0) : 0;
      total += _refundAmount(m, qty);
    }
    return total;
  }

  bool get _hasReturnQuantity => _returnQuantities.values.any((q) => q > 0);

  // 入力内容を検証したうえで返品をサーバーに登録し、返品レシートを印字する
  Future<void> _submitRefund() async {
    if (!_twoAuthenticated) {
      showMessage(context, '2名以上の従業員認証が必要です', MessageType.error);
      return;
    }
    if (_saleData == null || !_hasReturnQuantity) {
      showMessage(context, '返品する数量を1以上指定してください', MessageType.error);
      return;
    }
    final details = <Map<String, dynamic>>[];
    for (final entry in _returnQuantities.entries) {
      if (entry.value > 0) {
        details.add({'saledetail_id': entry.key, 'quantity': entry.value});
      }
    }
    final ok = await confirm(
      context,
      title: '${yen(_totalRefundAmount)} を返金しますか？',
      message: '返品を登録し、返品レシートを印刷します。',
      okLabel: '返金する',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _submitLoading = true);
    final result = await RefundApi.createRefund(
      receiptNumber: _receiptNumberController.text.trim(),
      employeeIds: _employeeIds.whereType<int>().toList(),
      details: details,
    );
    if (!mounted) return;
    setState(() => _submitLoading = false);
    // 返品の承認は1回限り。成功後・期限切れのときは認証からやり直す
    if (result['success'] == true ||
        result['code'] == 'operator_approval_required') {
      OperatorApprovals.clear('refund');
      setState(() {
        _employeeIds.fillRange(0, _employeeIds.length, null);
        _employeeNames.fillRange(0, _employeeNames.length, null);
      });
    }
    if (result['success'] == true) {
      final totalRefund = result['total_refund_amount'] is int
          ? result['total_refund_amount'] as int
          : _totalRefundAmount;
      final refundReceiptNumber =
          result['refund_receipt_number']?.toString() ?? '';

      // 返品レシート用の明細（返品した行だけ）
      final refundDetailsForReceipt = <Map<String, dynamic>>[];
      if (_saleData != null && _saleData!['details'] != null) {
        for (final d in _saleData!['details'] as List<dynamic>) {
          final m = d as Map;
          final id = m['id'] as int?;
          final qty = id != null ? (_returnQuantities[id] ?? 0) : 0;
          if (qty <= 0) continue;
          final amount = _refundAmount(m, qty);
          refundDetailsForReceipt.add({
            'product_code': m['product_code'] ?? '',
            'product_name': m['product_name'] ?? '',
            'quantity': qty,
            'unit_price': amount ~/ qty,
            'subtotal': amount,
          });
        }
      }

      // サーバーが決めた返金の決済手段別内訳（元の会計の支払いに応じる）
      bool hadCash = false;
      final paymentSummary = <Map<String, dynamic>>[];
      for (final p in (result['payments'] as List<dynamic>?) ?? []) {
        final m = p as Map;
        final methodCode = _normalizePaymentCode(m['method']);
        final amount = _parseInt(m['amount'], fallback: 0);
        paymentSummary.add({
          'method': _paymentLabel(methodCode),
          'amount': amount,
        });
        if (methodCode == 0) hadCash = true;
      }

      try {
        await ReceiptPrinter.printRefundReceipt(
          refundReceiptNumber: refundReceiptNumber,
          totalRefundAmount: totalRefund,
          details: refundDetailsForReceipt,
          paymentMethods: paymentSummary,
          openDrawer: hadCash,
        );
      } catch (e) {
        debugPrint('返品レシート印刷エラー: $e');
      }

      if (!mounted) return;
      showMessage(
        context,
        '返品・返金を登録しました。返金: ${paymentSummary.map((p) => '${p['method']} ${yen(p['amount'] as num?)}').join('、')}',
        MessageType.success,
      );

      // サーバーが返品数量分だけ在庫・売上を調整するため、
      // 未返品分の再会計は不要（元の会計が残数量分そのまま有効）。
      // 残数量はサーバー側で管理され、後から追加の返品も可能。
      setState(() {
        _saleData = null;
        _returnQuantities.clear();
      });
    } else {
      showMessage(
        context,
        result['message']?.toString() ?? 'エラーが発生しました',
        MessageType.error,
      );
    }
  }

  // 様々な型で来る値をintへ変換する(変換できなければfallbackを返す)
  int _parseInt(Object? value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final s = value.toString();
    return int.tryParse(s) ?? fallback;
  }

  // 支払方法を数値コード(0:現金/1:カード/2:バーコード決済)に正規化する
  int _normalizePaymentCode(Object? value) {
    // まず数値として解釈
    final intCode = _parseInt(value, fallback: -1);
    if (intCode >= 0) return intCode;

    final s = value?.toString().toLowerCase() ?? '';
    switch (s) {
      case 'cash':
        return 0;
      case 'card':
        return 1;
      case 'barcode':
      case 'barcode_payment':
        return 2;
      default:
        return -1;
    }
  }

  // 支払方法コードを日本語ラベルに変換する
  String _paymentLabel(int methodCode) {
    switch (methodCode) {
      case 0:
        return '現金';
      case 1:
        return 'カード';
      case 2:
        return 'バーコード決済';
      case 3:
        return '電子マネー';
      case 4:
        return 'ポイント';
      case 5:
        return '商品券';
      case 6:
        return '掛売';
      default:
        return 'その他';
    }
  }

  // 手順の見出し（番号・題名・終わったかどうか）
  Widget _step(int number, String title, bool done, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: done ? AppColors.success : AppColors.primary,
                  foregroundColor: Colors.white,
                  child: done
                      ? const Icon(Icons.check, size: 20)
                      : Text('$number'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final sale = _saleData?['sale'] as Map?;
    return Scaffold(
      appBar: const AppHeader('返品・返金', subtitle: '2人で確認してから返金します'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _step(
            1,
            '返品できる人が2人で確認します',
            _twoAuthenticated,
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < 2; i++)
                  _employeeIds[i] != null
                      ? Chip(
                          avatar: const Icon(
                            Icons.check_circle,
                            color: AppColors.success,
                          ),
                          label: Text('${i + 1}人目: ${_employeeNames[i] ?? ''}'),
                          onDeleted: () => setState(() {
                            _employeeIds[i] = null;
                            _employeeNames[i] = null;
                          }),
                          deleteButtonTooltipMessage: 'やり直す',
                        )
                      : ElevatedButton.icon(
                          onPressed: () => _authenticate(i),
                          icon: const Icon(Icons.person_add),
                          label: Text('${i + 1}人目を確認する'),
                        ),
              ],
            ),
          ),
          _step(
            2,
            'レシートを探します',
            _saleData != null,
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 360,
                  child: TextField(
                    controller: _receiptNumberController,
                    decoration: const InputDecoration(
                      labelText: 'レシート番号',
                      hintText: '例: shop-store-1-00000001',
                    ),
                    onSubmitted: (_) => _twoAuthenticated ? _loadSale() : null,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _openQrScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('QRを読み取る'),
                ),
                ElevatedButton.icon(
                  onPressed: _saleLoading || !_twoAuthenticated
                      ? null
                      : _loadSale,
                  icon: const Icon(Icons.search),
                  label: Text(_saleLoading ? '探しています…' : '探す'),
                ),
                if (!_twoAuthenticated)
                  const Text(
                    '先に2人の確認をしてください',
                    style: TextStyle(color: AppColors.secondary),
                  ),
              ],
            ),
          ),
          if (_saleData != null)
            _step(
              3,
              '返品する数を選びます',
              _hasReturnQuantity,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'レシート ${sale?['receipt_number'] ?? ''}　合計 ${yen(sale?['total_amount'] as num?)}',
                    style: const TextStyle(color: AppColors.secondary),
                  ),
                  const SizedBox(height: 8),
                  for (final d in _saleData!['details'] as List<dynamic>)
                    _detailRow(d as Map),
                  const Divider(height: 24),
                  LabelValue(
                    '返金する金額',
                    yen(_totalRefundAmount),
                    size: 30,
                    bold: true,
                    color: AppColors.danger,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 64,
                    child: ElevatedButton.icon(
                      onPressed: _submitLoading || !_hasReturnQuantity
                          ? null
                          : _submitRefund,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                      ),
                      icon: const Icon(Icons.replay),
                      label: Text(
                        _submitLoading ? '処理しています…' : '返品・返金する',
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailRow(Map<dynamic, dynamic> m) {
    final id = m['id'] as int?;
    if (id == null) return const SizedBox.shrink();
    final soldQty = (m['quantity'] as num?)?.toInt() ?? 0;
    final unitPrice = (m['unit_price'] as num?)?.toInt() ?? 0;
    // 返品可能数量（部分返品済みの場合は残数）。旧サーバーは販売数にフォールバック
    final refundable = (m['refundable_quantity'] as num?)?.toInt() ?? soldQty;
    final quantity = _returnQuantities[id] ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m['product_name'] as String? ?? '',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${yen(unitPrice)} × $soldQty'
                  '${refundable < soldQty ? '（あと$refundable個まで返品できます）' : ''}',
                  style: const TextStyle(color: AppColors.secondary),
                ),
              ],
            ),
          ),
          QuantityStepper(
            quantity: quantity,
            onMinus: quantity <= 0
                ? null
                : () => setState(() => _returnQuantities[id] = quantity - 1),
            onPlus: quantity >= refundable
                ? null
                : () => setState(() => _returnQuantities[id] = quantity + 1),
          ),
          SizedBox(
            width: 96,
            child: Text(
              quantity == 0 ? '' : yen(_refundAmount(m, quantity)),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
