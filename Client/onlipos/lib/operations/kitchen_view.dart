// 厨房への注文の一覧（受付待ち → 調理中 → 提供済み）。10秒ごとに自動更新する
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:onlipos/operations/common.dart';
import 'package:onlipos/sale/sale_extras_api.dart';

class KitchenView extends StatefulWidget {
  const KitchenView({super.key});

  @override
  State<KitchenView> createState() => _KitchenViewState();
}

class _KitchenViewState extends State<KitchenView> {
  List<Map<String, dynamic>> _orders = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await SaleExtrasApi.kitchenOrders();
    if (!mounted || result['success'] != true) return;
    setState(
      () => _orders = (result['kitchen_orders'] as List<dynamic>)
          .cast<Map<String, dynamic>>(),
    );
  }

  Future<void> _update(int id, String event) async {
    final result = await SaleExtrasApi.updateKitchenOrder(id, event);
    if (result['success'] != true) showResult(result, '');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('厨房')),
      body: _orders.isEmpty
          ? const Center(child: Text('注文はありません'))
          : GridView.extent(
              maxCrossAxisExtent: 320,
              padding: const EdgeInsets.all(12),
              children: [
                for (final order in _orders)
                  Card(
                    color: order['status'] == 'waiting'
                        ? Colors.red[50]
                        : Colors.amber[50],
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '卓 ${order['table_number'] ?? '-'}'
                            '${order['source'] == 'self_order' ? '（セルフ）' : ''}'
                            '  ${shortTime(order['created_at'])}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Expanded(
                            child: ListView(
                              children: [
                                for (final item
                                    in (order['items'] as List<dynamic>))
                                  Text(
                                    '${item['name']} ×${item['quantity']}'
                                    '${(item['options'] as List<dynamic>? ?? []).isEmpty ? '' : '\n  ${(item['options'] as List<dynamic>).join('・')}'}',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () =>
                                      _update(order['id'] as int, 'advance'),
                                  child: Text(
                                    order['status'] == 'waiting'
                                        ? '調理開始'
                                        : '提供済み',
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '取消',
                                icon: const Icon(Icons.close),
                                onPressed: () =>
                                    _update(order['id'] as int, 'cancel'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
