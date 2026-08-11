/// 返品・返金処理画面。不正防止のため従業員2名の認証を必須とし、
/// レシート番号(手入力またはQR読み取り)で対象の会計を検索、
/// 商品ごとに返品数量を指定してサーバーへ登録・返品レシートを印字する。
library;

import 'package:flutter/material.dart';
import 'package:onlipos/login/login_api.dart';
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
  // 従業員認証（2名以上）
  final List<TextEditingController> _codeControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  final List<TextEditingController> _pinControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  final List<int?> _employeeIds = [null, null];
  final List<String?> _employeeNames = [null, null];
  final List<bool> _authLoading = [false, false];

  final TextEditingController _receiptNumberController =
      TextEditingController();
  bool _saleLoading = false;
  Map<String, dynamic>? _saleData;

  // 返品する数量（saledetail id -> quantity to return）
  final Map<int, int> _returnQuantities = {};
  bool _submitLoading = false;

  @override
  void dispose() {
    for (final c in _codeControllers) {
      c.dispose();
    }
    for (final c in _pinControllers) {
      c.dispose();
    }
    _receiptNumberController.dispose();
    super.dispose();
  }

  bool get _twoAuthenticated =>
      _employeeIds[0] != null && _employeeIds[1] != null;

  // index番目の担当者枠を担当者コード・PINで認証し、返品権限と重複認証を確認する
  Future<void> _authenticate(int index) async {
    final code = _codeControllers[index].text.trim();
    final pin = _pinControllers[index].text.trim();
    if (code.isEmpty || pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('担当者コードとパスワードを入力してください'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _authLoading[index] = true);
    final result = await LoginApi.verifyEmployee(code: code, pin: pin);
    if (!mounted) return;
    setState(() => _authLoading[index] = false);

    if (result['success'] == true) {
      final newId = result['employee_id'] as int?;
      // 同一担当者による二重認証を防ぐ
      final otherIndex = 1 - index;
      if (newId != null && _employeeIds[otherIndex] == newId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('同一の担当者による2名認証はできません'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      // 返品権限チェック
      final permissions =
          (result['permissions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      if (!permissions.contains('refund')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('この操作の権限がありません（返品）'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      setState(() {
        _employeeIds[index] = newId;
        _employeeNames[index] = result['employee_name'] as String?;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? '認証に失敗しました'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('レシート番号を入力するかQRで読み取ってください'),
          backgroundColor: Colors.red,
        ),
      );
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
      if (alreadyRefunded) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('この会計はすでに返品済みです'),
              backgroundColor: Colors.red,
            ),
          );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? '会計を取得できませんでした'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 指定された返品数量から返金合計額を計算する
  int get _totalRefundAmount {
    if (_saleData == null || _saleData!['details'] == null) return 0;
    int total = 0;
    for (final d in _saleData!['details'] as List<dynamic>) {
      final m = d as Map;
      final id = m['id'] as int?;
      final unitPrice = (m['unit_price'] as num?)?.toInt() ?? 0;
      final qty = id != null ? (_returnQuantities[id] ?? 0) : 0;
      total += unitPrice * qty;
    }
    return total;
  }

  bool get _hasReturnQuantity => _returnQuantities.values.any((q) => q > 0);

  // 入力内容を検証したうえで返品をサーバーに登録し、返品レシートを印字する
  Future<void> _submitRefund() async {
    if (!_twoAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('2名以上の従業員認証が必要です'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_saleData == null || !_hasReturnQuantity) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('返品する数量を1以上指定してください'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final details = <Map<String, dynamic>>[];
    for (final entry in _returnQuantities.entries) {
      if (entry.value > 0) {
        details.add({'saledetail_id': entry.key, 'quantity': entry.value});
      }
    }
    setState(() => _submitLoading = true);
    final result = await RefundApi.createRefund(
      receiptNumber: _receiptNumberController.text.trim(),
      employeeIds: _employeeIds.whereType<int>().toList(),
      details: details,
    );
    if (!mounted) return;
    setState(() => _submitLoading = false);
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
          final unitPrice = (m['unit_price'] as num?)?.toInt() ?? 0;
          refundDetailsForReceipt.add({
            'product_code': m['product_code'] ?? '',
            'product_name': m['product_name'] ?? '',
            'quantity': qty,
            'unit_price': unitPrice,
            'subtotal': unitPrice * qty,
          });
        }
      }

      // 元の会計の支払方法（ラベル付き）と、現金が含まれるか
      bool hadCash = false;
      final paymentSummary = <Map<String, dynamic>>[];
      if (_saleData != null && _saleData!['payments'] != null) {
        for (final p in _saleData!['payments'] as List<dynamic>) {
          final m = p as Map;
          final methodCode = _normalizePaymentCode(m['method']);
          final amount = _parseInt(m['amount'], fallback: 0);
          final label = _paymentLabel(methodCode);
          paymentSummary.add({'method': label, 'amount': amount});
          if (methodCode == 0) {
            hadCash = true;
          }
        }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('返品・返金を登録しました。返金合計: ¥$totalRefund'),
          backgroundColor: Colors.green,
        ),
      );

      // サーバーが返品数量分だけ在庫・売上を調整するため、
      // 未返品分の再会計は不要（元の会計が残数量分そのまま有効）。
      // 残数量はサーバー側で管理され、後から追加の返品も可能。
      setState(() {
        _saleData = null;
        _returnQuantities.clear();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'エラーが発生しました'),
          backgroundColor: Colors.red,
        ),
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
      default:
        return 'その他';
    }
  }

  // 「1.従業員認証 → 2.レシート検索 → 3.返品数量入力」の3ステップを縦に並べる
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('返品・返金')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '1. 従業員2名以上で認証してください',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ...List.generate(2, (i) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '従業員${i + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (_employeeIds[i] != null)
                        Text(
                          '認証済み: ${_employeeNames[i] ?? ''} (ID: ${_employeeIds[i]})',
                          style: const TextStyle(color: Colors.green),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _codeControllers[i],
                                decoration: const InputDecoration(
                                  labelText: '担当者コード',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _pinControllers[i],
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'パスワード',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _authLoading[i]
                                  ? null
                                  : () => _authenticate(i),
                              child: _authLoading[i]
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('認証'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
            const Text(
              '2. レシート番号を入力するかQRで読み取ってください',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _receiptNumberController,
                    decoration: const InputDecoration(
                      labelText: 'レシート番号',
                      border: OutlineInputBorder(),
                      hintText: '例: Test-Store-1-00000001',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _openQrScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'QRで読み取る',
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saleLoading || !_twoAuthenticated
                      ? null
                      : _loadSale,
                  child: _saleLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('検索'),
                ),
              ],
            ),
            if (_saleData != null) ...[
              const SizedBox(height: 16),
              const Text(
                '3. 返品する数量を入力（1個単位）',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'レシート: ${_saleData!['sale']?['receipt_number'] ?? ''}  合計: ¥${_saleData!['sale']?['total_amount'] ?? 0}',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              ...((_saleData!['details'] as List<dynamic>).map((d) {
                final m = d as Map;
                final id = m['id'] as int?;
                final name = m['product_name'] as String? ?? '';
                final soldQty = (m['quantity'] as num?)?.toInt() ?? 0;
                final unitPrice = (m['unit_price'] as num?)?.toInt() ?? 0;
                // 返品可能数量（部分返品済みの場合は残数）。旧サーバーは販売数にフォールバック
                final refundableQty =
                    (m['refundable_quantity'] as num?)?.toInt() ?? soldQty;
                if (id == null) return const SizedBox.shrink();
                final returnQty = _returnQuantities[id] ?? 0;
                return Card(
                  child: ListTile(
                    title: Text(name),
                    subtitle: Text(
                      refundableQty < soldQty
                          ? '販売: $soldQty 個 (返品可能: $refundableQty 個)  @ ¥$unitPrice'
                          : '販売: $soldQty 個  @ ¥$unitPrice',
                    ),
                    trailing: SizedBox(
                      width: 120,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: returnQty <= 0
                                ? null
                                : () {
                                    setState(
                                      () =>
                                          _returnQuantities[id] = returnQty - 1,
                                    );
                                  },
                          ),
                          Text(
                            '$returnQty',
                            style: const TextStyle(fontSize: 18),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: returnQty >= refundableQty
                                ? null
                                : () {
                                    setState(
                                      () =>
                                          _returnQuantities[id] = returnQty + 1,
                                    );
                                  },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              })),
              const SizedBox(height: 8),
              Text(
                '返金合計: ¥$_totalRefundAmount',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitLoading || !_hasReturnQuantity
                      ? null
                      : _submitRefund,
                  icon: _submitLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle),
                  label: Text(_submitLoading ? '処理中...' : '返品・返金する'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
