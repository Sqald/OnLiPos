import 'dart:async';
import 'package:flutter/material.dart';
import 'package:onlipos/sale/transfer_order_api.dart';
import 'package:onlipos/sale/sale_scan_view.dart';

/// ホスト機の待ち受けモード画面。
/// 同一店舗内のクライアント機から転送された注文を一覧表示し、
/// 受け取るとカートにロードして会計画面に遷移する。
class HostWaitingView extends StatefulWidget {
  final String operatorName;
  final int operatorId;

  const HostWaitingView({
    super.key,
    required this.operatorName,
    required this.operatorId,
  });

  @override
  State<HostWaitingView> createState() => _HostWaitingViewState();
}

class _HostWaitingViewState extends State<HostWaitingView> {
  List<TransferOrderEntry> _transfers = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  int _secondsUntilRefresh = 5;

  @override
  void initState() {
    super.initState();
    _loadTransfers();
    // 5秒ごとに自動更新
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _secondsUntilRefresh--);
      if (_secondsUntilRefresh <= 0) {
        _secondsUntilRefresh = 5;
        _loadTransfers();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTransfers() async {
    try {
      final list = await TransferOrderApi.getAllTransfers();
      if (mounted) {
        setState(() {
          _transfers = list;
          _isLoading = false;
          _secondsUntilRefresh = 5;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _claimTransfer(TransferOrderEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('転送注文を受け取りますか？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('担当: ${entry.operatorName}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (entry.tableNumber != null)
              Text('卓番: ${entry.tableNumber}',
                  style: const TextStyle(color: Colors.orange)),
            const SizedBox(height: 8),
            Text('${entry.itemCount}点  ¥${entry.totalAmount}',
                style: const TextStyle(fontSize: 16)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('受け取る'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final claimed = await TransferOrderApi.claimTransfer(entry.id);
      if (!mounted) return;
      // 会計画面に遷移（カート内容がプリロードされた状態）
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => SaleScanView(
            operatorName: widget.operatorName,
            operatorId: widget.operatorId,
            storeMode: 'standard',
            initialItems: claimed.items,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('受け取りに失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _elapsed(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inHours > 0) return '${diff.inHours}時間前';
    if (diff.inMinutes > 0) return '${diff.inMinutes}分前';
    return '${diff.inSeconds}秒前';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('待ち受けモード'),
        backgroundColor: const Color(0xFF1D1D1D),
        foregroundColor: Colors.white,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                '${_secondsUntilRefresh}秒後に更新',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTransfers,
            tooltip: '今すぐ更新',
          ),
        ],
      ),
      backgroundColor: const Color(0xFF2A2A2A),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _transfers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_outlined, size: 80, color: Colors.grey[600]),
                      const SizedBox(height: 16),
                      Text(
                        '転送待ちの注文はありません',
                        style: TextStyle(fontSize: 20, color: Colors.grey[400]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'クライアント機からの転送を待っています',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _transfers.length,
                  itemBuilder: (context, index) {
                    final t = _transfers[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: const Color(0xFF3A3A3A),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            // アイコン
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2D89EF),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.send,
                                  color: Colors.white, size: 28),
                            ),
                            const SizedBox(width: 16),
                            // 情報
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '担当: ${t.operatorName}',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white),
                                  ),
                                  if (t.tableNumber != null)
                                    Text(
                                      '卓 ${t.tableNumber}',
                                      style: const TextStyle(
                                          color: Colors.orange, fontSize: 14),
                                    ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${t.itemCount}点  ¥${t.totalAmount}',
                                    style: const TextStyle(
                                        fontSize: 16, color: Colors.white70),
                                  ),
                                  Text(
                                    _elapsed(t.createdAt),
                                    style: TextStyle(
                                        fontSize: 13, color: Colors.grey[500]),
                                  ),
                                ],
                              ),
                            ),
                            // 受け取るボタン
                            SizedBox(
                              width: 120,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: () => _claimTransfer(t),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('受け取る',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
