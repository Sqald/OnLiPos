import 'package:flutter/material.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:onlipos/refund/qr_scan_receipt_view.dart';
import 'package:onlipos/refund/refund_api.dart';
import 'package:onlipos/sale/escpos/lan_recipt_api.dart';
import 'package:onlipos/sale/send_to_api.dart';

/// 領収書発行画面。
/// レシート番号（QR読取 or 手入力）で会計を検索し、宛名・但し書きを入力して
/// 発行を記録（ジャーナル）した上で領収書を印字する。再発行時はその旨を印字する。
class ReceiptIssueView extends StatefulWidget {
  final String operatorName;
  final int operatorId;

  const ReceiptIssueView({
    super.key,
    required this.operatorName,
    required this.operatorId,
  });

  @override
  State<ReceiptIssueView> createState() => _ReceiptIssueViewState();
}

class _ReceiptIssueViewState extends State<ReceiptIssueView> {
  final _receiptNumberController = TextEditingController();
  final _addresseeController = TextEditingController();
  final _purposeController = TextEditingController(text: 'お品代として');

  bool _isLoading = false;
  bool _isIssuing = false;
  Map<String, dynamic>? _sale; // sale_by_receipt の sale 部

  @override
  void dispose() {
    _receiptNumberController.dispose();
    _addresseeController.dispose();
    _purposeController.dispose();
    super.dispose();
  }

  void _showMessage(String msg, {bool error = false}) {
    showMessage(context, msg, error ? MessageType.error : MessageType.success);
  }

  // QRコードスキャン画面を開き、読み取ったレシート番号で検索する
  Future<void> _scanQr() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const QrScanReceiptView()),
    );
    if (scanned != null && scanned.isNotEmpty) {
      _receiptNumberController.text = scanned;
      await _search();
    }
  }

  // レシート番号で対象の会計をサーバーから検索する
  Future<void> _search() async {
    final receiptNumber = _receiptNumberController.text.trim();
    if (receiptNumber.isEmpty) {
      _showMessage('レシート番号を入力してください', error: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _sale = null;
    });

    final result = await RefundApi.getSaleByReceipt(receiptNumber);
    if (!mounted) return;

    setState(() => _isLoading = false);
    if (result['success'] == true) {
      setState(() => _sale = result['sale'] as Map<String, dynamic>);
    } else {
      _showMessage(result['message']?.toString() ?? '会計が見つかりません', error: true);
    }
  }

  // 領収書発行をサーバーに記録し、正式領収書を印字する
  Future<void> _issue() async {
    final sale = _sale;
    if (sale == null || _isIssuing) return;

    setState(() => _isIssuing = true);
    try {
      final result = await SentToApi().issueReceipt(
        saleId: (sale['id'] as num).toInt(),
        employeeId: widget.operatorId,
        addressee: _addresseeController.text.trim(),
        purpose: _purposeController.text.trim(),
      );
      if (!mounted) return;

      if (result['success'] == true) {
        final reissue = result['reissue'] == true;
        final receipt = result['receipt'] as Map<String, dynamic>;
        await ReceiptPrinter.printFormalReceipt(
          receipt: receipt,
          reissue: reissue,
        );
        if (!mounted) return;
        _showMessage(reissue ? '領収書を再発行しました' : '領収書を発行しました');
        Navigator.of(context).pop();
      } else {
        _showMessage(result['message']?.toString() ?? '発行に失敗しました', error: true);
      }
    } catch (e) {
      if (mounted) _showMessage('通信エラー: $e', error: true);
    } finally {
      if (mounted) setState(() => _isIssuing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader('領収書', subtitle: '担当: ${widget.operatorName}'),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSearchSection(),
                  const SizedBox(height: 24),
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (_sale != null)
                    _buildIssueSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '領収書を出す会計を探す',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _receiptNumberController,
                decoration: const InputDecoration(
                  labelText: 'レシート番号',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _search,
                icon: const Icon(Icons.search),
                label: const Text('探す'),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 56,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _scanQr,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('QRを読み取る'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIssueSection() {
    final sale = _sale!;
    final total = (sale['total_amount'] as num?)?.toInt() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('レシート番号 ${sale['receipt_number']}'),
                const SizedBox(height: 4),
                Text(
                  '日時: ${sale['created_at']?.toString().substring(0, 19).replaceFirst('T', ' ') ?? ''}',
                ),
                const SizedBox(height: 8),
                Text(
                  yen(total),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (total >= 50000)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '5万円以上のため、収入印紙が必要です',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _addresseeController,
          decoration: const InputDecoration(
            labelText: '宛名',
            helperText: '空欄にすると、手書き用の線を印刷します',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _purposeController,
          decoration: const InputDecoration(
            labelText: '但し書き',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 64,
          child: ElevatedButton.icon(
            onPressed: _isIssuing ? null : _issue,
            icon: const Icon(Icons.print),
            label: _isIssuing
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('領収書を印刷する', style: TextStyle(fontSize: 20)),
          ),
        ),
      ],
    );
  }
}
