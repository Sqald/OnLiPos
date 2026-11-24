// ホスト機の待ち受けモード画面（Widget定義）。
// 5秒ごとに転送注文一覧をポーリングして表示し、受け取り操作を提供する。
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_header.dart';
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

  // 転送注文一覧をサーバーから取得して画面を更新する
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

  // 確認ダイアログを表示後、転送注文を受け取り会計画面へ遷移する
  Future<void> _claimTransfer(TransferOrderEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('この会計を受け取りますか？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '担当: ${entry.operatorName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (entry.tableNumber != null)
              Text(
                '卓 ${entry.tableNumber}',
                style: const TextStyle(color: AppColors.warning),
              ),
            const SizedBox(height: 8),
            Text(
              '${entry.itemCount}点　${yen(entry.totalAmount)}',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('やめる'),
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
        showMessage(context, '受け取りに失敗しました: $e', MessageType.error);
      }
    }
  }

  // 作成からの経過時間を「◯時間前」等の文字列に変換する
  String _elapsed(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inHours > 0) return '${diff.inHours}時間前';
    if (diff.inMinutes > 0) return '${diff.inMinutes}分前';
    return '${diff.inSeconds}秒前';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        '待ち受け',
        subtitle: '$_secondsUntilRefresh秒後に更新します',
        actions: [
          OutlinedButton.icon(
            onPressed: _loadTransfers,
            icon: const Icon(Icons.refresh, size: 20),
            label: const Text('いま更新する'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _transfers.isEmpty
          ? const EmptyState(
              icon: Icons.inbox_outlined,
              title: '送られてきた会計はありません',
              message: 'クライアント機から送られると、ここに表示されます',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _transfers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final t = _transfers[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.move_to_inbox,
                          size: 36,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${yen(t.totalAmount)}（${t.itemCount}点）',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                [
                                  if (t.tableNumber != null)
                                    '卓 ${t.tableNumber}',
                                  '担当: ${t.operatorName}',
                                  _elapsed(t.createdAt),
                                ].join('　'),
                                style: const TextStyle(
                                  color: AppColors.secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => _claimTransfer(t),
                          child: const Text('受け取る'),
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
