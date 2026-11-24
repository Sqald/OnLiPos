// サーバーに受け付けられなかったオフライン会計の確認と再送
import 'dart:convert';

import 'package:flutter/material.dart';
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('送信できなかった会計')),
      body: _rows.isEmpty
          ? const Center(child: Text('ありません'))
          : ListView(
              children: [
                for (final row in _rows)
                  ListTile(
                    title: Text(
                      '${row['receipt_number']}  ¥${(jsonDecode(row['payload'] as String) as Map)['sale']['total_amount']}',
                    ),
                    subtitle: Text(
                      '${row['created_at']}\n${row['last_error']}',
                    ),
                    isThreeLine: true,
                    trailing: OutlinedButton(
                      onPressed: () => _retry(row['id'] as int),
                      child: const Text('再送'),
                    ),
                  ),
              ],
            ),
    );
  }
}
