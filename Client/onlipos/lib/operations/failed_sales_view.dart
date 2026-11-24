// サーバーに受け付けられなかったオフライン会計の確認と再送
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_session.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:onlipos/sale/offline_sale_repository.dart';
import 'package:onlipos/sale/send_to_api.dart';

class FailedSalesView extends StatefulWidget {
  const FailedSalesView({super.key});

  @override
  State<FailedSalesView> createState() => _FailedSalesViewState();
}

class _FailedSalesViewState extends State<FailedSalesView> {
  final _repository = OfflineSaleRepository();
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await _repository.getFailed();
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _retry(int id) async {
    await _repository.retry(id);
    await SentToApi().drainOfflineQueue();
    await _load();
    await AppSession.instance.refreshCounts();
    if (!mounted) return;
    final stillFailed = _rows.any((r) => r['id'] == id);
    showMessage(
      context,
      stillFailed ? '送信できませんでした。理由を確認してください' : '送信しました',
      stillFailed ? MessageType.error : MessageType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader('送信できなかった会計'),
      body: _rows.isEmpty
          ? const EmptyState(icon: Icons.cloud_done, title: '送信できなかった会計はありません')
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'サーバーに受け付けられなかった会計です。理由を確認し、直したあとに「もう一度送信」を押してください。'
                  '解決しないときは、管理者に連絡してください。会計の内容はこの端末に残っています。',
                  style: TextStyle(fontSize: 16, color: AppColors.secondary),
                ),
                const SizedBox(height: 16),
                for (final row in _rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(
                          '${yen((jsonDecode(row['payload'] as String) as Map)['sale']['total_amount'] as num?)}　${row['receipt_number']}',
                        ),
                        subtitle: Text(
                          '${row['created_at'].toString().split('.').first.replaceFirst('T', ' ')}\n理由: ${row['last_error'] ?? '不明'}',
                        ),
                        isThreeLine: true,
                        trailing: ElevatedButton(
                          onPressed: () => _retry(row['id'] as int),
                          child: const Text('もう一度送信'),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
