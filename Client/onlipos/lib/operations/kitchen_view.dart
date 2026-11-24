// 厨房への注文の一覧（受付待ち → 調理中 → 提供済み）。10秒ごとに自動更新する
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_header.dart';
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

  Future<void> _cancel(Map<String, dynamic> order) async {
    final ok = await confirm(
      context,
      title: 'この注文を取り消しますか？',
      message: '卓 ${order['table_number'] ?? '-'} の注文を厨房の一覧から消します。',
      okLabel: '取り消す',
      danger: true,
    );
    if (ok) await _update(order['id'] as int, 'cancel');
  }

  Future<void> _update(int id, String event) async {
    final result = await SaleExtrasApi.updateKitchenOrder(id, event);
    if (result['success'] != true) showResult(result, '');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader('厨房', subtitle: '${_orders.length}件の注文　10秒ごとに更新'),
      body: _orders.isEmpty
          ? const EmptyState(
              icon: Icons.soup_kitchen_outlined,
              title: 'いま待っている注文はありません',
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 360,
                mainAxisExtent: 320,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: _orders.length,
              itemBuilder: (context, i) => _orderCard(_orders[i]),
            ),
    );
  }

  Widget _orderCard(Map<String, dynamic> order) {
    final waiting = order['status'] == 'waiting';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 8,
            color: waiting ? AppColors.danger : const Color(0xFFF5A524),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '卓 ${order['table_number'] ?? '-'}'
                    '${order['source'] == 'self_order' ? '（セルフ）' : ''}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                StatusBadge(
                  waiting ? '受付待ち' : '調理中',
                  type: waiting ? MessageType.error : MessageType.warning,
                ),
                IconButton(
                  tooltip: 'この注文を取り消す',
                  icon: const Icon(Icons.close),
                  onPressed: () => _cancel(order),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '${shortTime(order['created_at'])} 注文',
              style: const TextStyle(color: AppColors.secondary),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final item in (order['items'] as List<dynamic>)) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${item['name']}',
                          style: const TextStyle(fontSize: 19),
                        ),
                      ),
                      Text(
                        '×${item['quantity']}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if ((item['options'] as List<dynamic>? ?? []).isNotEmpty)
                    Text(
                      (item['options'] as List<dynamic>).join('・'),
                      style: const TextStyle(color: AppColors.warning),
                    ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ElevatedButton(
              onPressed: () => _update(order['id'] as int, 'advance'),
              style: waiting
                  ? null
                  : ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                    ),
              child: Text(waiting ? '調理を始める' : '提供済みにする'),
            ),
          ),
        ],
      ),
    );
  }
}
