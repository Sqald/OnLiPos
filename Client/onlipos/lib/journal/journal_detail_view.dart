/// ジャーナル明細画面。一覧から選択された1件のジャーナル(売上・返品・
/// レジ操作など)の詳細を表示し、売上/返品については再印字も行う。
library;

import 'package:flutter/material.dart';
import 'package:onlipos/journal/journal_api.dart';
import 'package:onlipos/sale/escpos/lan_recipt_api.dart';

class JournalDetailView extends StatefulWidget {
  final int employeeId;
  final Map<String, dynamic> summary;

  const JournalDetailView({
    super.key,
    required this.employeeId,
    required this.summary,
  });

  @override
  State<JournalDetailView> createState() => _JournalDetailViewState();
}

class _JournalDetailViewState extends State<JournalDetailView> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _entry;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ジャーナル詳細をサーバーから取得する
  Future<void> _load() async {
    final result = await JournalApi.fetchDetail(
      employeeId: widget.employeeId,
      id: widget.summary['id'] as int,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _entry = result['entry'] as Map<String, dynamic>;
        _loading = false;
      });
    } else {
      setState(() {
        _error = result['message']?.toString();
        _loading = false;
      });
    }
  }

  // ジャーナル種別(売上/返品)に応じてレシートを再印字する
  Future<void> _reprint() async {
    final entry = _entry;
    if (entry == null) return;

    setState(() => _printing = true);
    try {
      final type = entry['entry_type'] as String? ?? '';
      final payload = entry['payload'] as Map<String, dynamic>? ?? {};

      if (type == 'sale') {
        await _reprintSale(payload);
      } else if (type == 'refund') {
        await _reprintRefund(payload);
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('再印字しました')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('印字エラー: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  // 売上ジャーナルのpayloadから明細・支払方法を復元しレシートを印字する
  Future<void> _reprintSale(Map<String, dynamic> payload) async {
    final details = (payload['details'] as List? ?? []).map((d) {
      final m = d as Map<String, dynamic>;
      return {
        'product_name': m['product_name'] ?? '',
        'quantity': m['quantity'] ?? 1,
        'unit_price': m['unit_price'] ?? 0,
        'subtotal': m['subtotal'] ?? 0,
        'tax_rate': m['tax_rate'] ?? 10,
      };
    }).toList();

    final payments = (payload['payments'] as List? ?? []).map((p) {
      final m = p as Map<String, dynamic>;
      return {'method': m['method'] ?? 0, 'amount': m['amount'] ?? 0};
    }).toList();

    final printer = ReceiptPrinter();
    await printer.printReceipt(
      receiptNumber: payload['receipt_number']?.toString() ?? '',
      totalAmount: (payload['total_amount'] as num?)?.toInt() ?? 0,
      subtotalExTax: (payload['subtotal_ex_tax'] as num?)?.toInt() ?? 0,
      taxAmount: (payload['tax_amount'] as num?)?.toInt() ?? 0,
      details: details.cast<Map<String, dynamic>>(),
      paymentMethods: payments.cast<Map<String, dynamic>>(),
      change: 0,
      tenderedCash: 0,
    );
  }

  // 返品ジャーナルのpayloadから明細を復元し返品レシートを印字する
  Future<void> _reprintRefund(Map<String, dynamic> payload) async {
    final details = (payload['details'] as List? ?? []).map((d) {
      final m = d as Map<String, dynamic>;
      return {
        'product_name': m['product_name'] ?? '',
        'quantity': m['quantity'] ?? 1,
        'unit_price': m['unit_price'] ?? 0,
        'subtotal': m['subtotal'] ?? 0,
      };
    }).toList();

    await ReceiptPrinter.printRefundReceipt(
      refundReceiptNumber: payload['refund_receipt_number']?.toString() ?? '',
      totalRefundAmount: (payload['total_amount'] as num?)?.toInt() ?? 0,
      details: details.cast<Map<String, dynamic>>(),
      paymentMethods: const [],
      openDrawer: false,
    );
  }

  // 再印字ボタンを表示してよい種別(売上・返品)かどうか
  bool get _canReprint {
    final t = _entry?['entry_type'] as String?;
    return t == 'sale' || t == 'refund';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _entryTypeLabel(widget.summary['entry_type'] as String? ?? ''),
        ),
        actions: [
          if (_canReprint)
            TextButton.icon(
              onPressed: _printing ? null : _reprint,
              icon: _printing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.print, color: Colors.white),
              label: const Text('再印字', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  // 読み込み状態・エラー・種別ごとの表示内容を組み立てる
  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('再試行')),
          ],
        ),
      );
    }

    final entry = _entry!;
    final payload = entry['payload'] as Map<String, dynamic>? ?? {};
    final type = entry['entry_type'] as String? ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderCard(entry: entry),
          const SizedBox(height: 12),
          if (type == 'sale') _SalePayloadCard(payload: payload),
          if (type == 'refund') _RefundPayloadCard(payload: payload),
          if (type == 'cash_pickup') _PickupPayloadCard(payload: payload),
          if (type == 'register_open' ||
              type == 'cash_check' ||
              type == 'register_close')
            _CashPayloadCard(payload: payload, type: type),
        ],
      ),
    );
  }
}

// ── ヘッダカード ──────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _HeaderCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row('種別', _entryTypeLabel(entry['entry_type'] as String? ?? '')),
            if (entry['receipt_number'] != null)
              _Row('レシート番号', entry['receipt_number'].toString()),
            _Row('日時', _fmtTime(entry['printed_at'] as String? ?? '')),
            _Row('POS', entry['pos_name']?.toString() ?? ''),
            if (entry['employee_name'] != null)
              _Row('担当者', entry['employee_name'].toString()),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 売上 payload ──────────────────────────────────────────────────────────────

class _SalePayloadCard extends StatelessWidget {
  final Map<String, dynamic> payload;
  const _SalePayloadCard({required this.payload});

  @override
  Widget build(BuildContext context) {
    final details = (payload['details'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final payments = (payload['payments'] as List? ?? [])
        .cast<Map<String, dynamic>>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '明細',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        ...details.map((d) => _DetailRow(d)),
        const Divider(),
        _AmountRow('税抜小計', (payload['subtotal_ex_tax'] as num?)?.toInt() ?? 0),
        _AmountRow('消費税', (payload['tax_amount'] as num?)?.toInt() ?? 0),
        if ((payload['total_discount'] as num?)?.toInt() != 0)
          _AmountRow(
            '値引合計',
            -((payload['total_discount'] as num?)?.toInt() ?? 0),
            color: Colors.orange,
          ),
        _AmountRow(
          '合計',
          (payload['total_amount'] as num?)?.toInt() ?? 0,
          bold: true,
          large: true,
        ),
        const SizedBox(height: 8),
        const Text(
          '支払方法',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 4),
        ...payments.map((p) => _PaymentRow(p)),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final Map<String, dynamic> d;
  const _DetailRow(this.d);

  @override
  Widget build(BuildContext context) {
    final name = d['product_name']?.toString() ?? '';
    final qty = (d['quantity'] as num?)?.toInt() ?? 0;
    final price = (d['unit_price'] as num?)?.toInt() ?? 0;
    final sub = (d['subtotal'] as num?)?.toInt() ?? 0;
    final disc = (d['discount_amount'] as num?)?.toInt() ?? 0;
    final reason = d['discount_reason']?.toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(name)),
              Text(
                '$qty個 × ¥${_fmt(price)} = ¥${_fmt(sub)}',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
          if (disc > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '値引: -¥${_fmt(disc)}${reason != null ? "（$reason）" : ""}',
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final Map<String, dynamic> p;
  const _PaymentRow(this.p);

  static const _methodNames = {0: '現金', 1: 'カード', 2: 'バーコード決済'};

  @override
  Widget build(BuildContext context) {
    final method = (p['method'] as num?)?.toInt() ?? 0;
    final amount = (p['amount'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(_methodNames[method] ?? '不明'),
          const Spacer(),
          Text(
            '¥${_fmt(amount)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// ── 返品 payload ──────────────────────────────────────────────────────────────

class _RefundPayloadCard extends StatelessWidget {
  final Map<String, dynamic> payload;
  const _RefundPayloadCard({required this.payload});

  @override
  Widget build(BuildContext context) {
    final details = (payload['details'] as List? ?? [])
        .cast<Map<String, dynamic>>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (payload['original_receipt_number'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '元レシート番号: ${payload['original_receipt_number']}',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
        const Text(
          '返品明細',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        ...details.map((d) {
          final name = d['product_name']?.toString() ?? '';
          final qty = (d['quantity'] as num?)?.toInt() ?? 0;
          final sub = (d['subtotal'] as num?)?.toInt() ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(name)),
                Text(
                  '$qty個  ¥${_fmt(sub)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          );
        }),
        const Divider(),
        _AmountRow(
          '返品合計',
          (payload['total_amount'] as num?)?.toInt() ?? 0,
          bold: true,
          large: true,
          color: Colors.pink,
        ),
      ],
    );
  }
}

// ── 途中回収 payload ──────────────────────────────────────────────────────────

class _PickupPayloadCard extends StatelessWidget {
  final Map<String, dynamic> payload;
  const _PickupPayloadCard({required this.payload});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AmountRow(
              '回収金額',
              (payload['pickup_amount'] as num?)?.toInt() ?? 0,
              bold: true,
              large: true,
              color: const Color(0xFFE65100),
            ),
            if (payload['pickup_reason'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('理由: ${payload['pickup_reason']}'),
              ),
          ],
        ),
      ),
    );
  }
}

// ── レジ金 payload ────────────────────────────────────────────────────────────

class _CashPayloadCard extends StatelessWidget {
  final Map<String, dynamic> payload;
  final String type;
  const _CashPayloadCard({required this.payload, required this.type});

  @override
  Widget build(BuildContext context) {
    final denoms = payload['denominations'] as Map<String, dynamic>? ?? {};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AmountRow(
              '合計金額',
              (payload['total_amount'] as num?)?.toInt() ?? 0,
              bold: true,
              large: true,
            ),
            if (denoms.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('金種内訳', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              for (final entry in [
                ('10000円', 'yen_10000'),
                ('5000円', 'yen_5000'),
                ('1000円', 'yen_1000'),
                ('500円', 'yen_500'),
                ('100円', 'yen_100'),
                ('50円', 'yen_50'),
                ('10円', 'yen_10'),
                ('5円', 'yen_5'),
                ('1円', 'yen_1'),
              ])
                if ((denoms[entry.$2] as num?)?.toInt() != 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Text(entry.$1),
                        const Spacer(),
                        Text('× ${(denoms[entry.$2] as num?)?.toInt() ?? 0}枚'),
                      ],
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 共通ウィジェット ───────────────────────────────────────────────────────────

class _AmountRow extends StatelessWidget {
  final String label;
  final int amount;
  final bool bold;
  final bool large;
  final Color? color;

  const _AmountRow(
    this.label,
    this.amount, {
    this.bold = false,
    this.large = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: large ? 18 : 14,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text('¥${_fmt(amount)}', style: style),
        ],
      ),
    );
  }
}

// ── ユーティリティ ────────────────────────────────────────────────────────────

// ジャーナル種別コードを日本語ラベルに変換する
String _entryTypeLabel(String type) => switch (type) {
  'sale' => '売上',
  'refund' => '返品',
  'register_open' => 'レジ開設',
  'cash_check' => 'レジ金確認',
  'cash_pickup' => '途中回収',
  'register_close' => 'レジ精算',
  _ => type,
};

// 金額を3桁区切りのカンマ付き文字列に整形する
String _fmt(int n) => n.toString().replaceAllMapped(
  RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]},',
);

// ISO8601文字列を"YYYY-MM-DD HH:mm"形式のローカル時刻表示に変換する
String _fmtTime(String iso) {
  if (iso.isEmpty) return '';
  try {
    final dt = DateTime.parse(iso).toLocal();
    final y = dt.year;
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi';
  } catch (_) {
    return iso;
  }
}
