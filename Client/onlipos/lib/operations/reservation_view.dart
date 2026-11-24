// 本日の予約の確認と来店処理
import 'package:flutter/material.dart';
import 'package:onlipos/operations/common.dart';
import 'package:onlipos/sale/sale_extras_api.dart';

class ReservationView extends StatelessWidget {
  const ReservationView({super.key});

  static const _statuses = {
    'booked': '予約',
    'seated': '来店',
    'finished': '終了',
    'canceled': '取消',
    'no_show': '来店なし',
  };

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return ReloadableList(
      title: '本日の予約',
      load: () => SaleExtrasApi.reservations(today),
      listKey: 'reservations',
      emptyMessage: '本日の予約はありません',
      itemBuilder: (context, item, reload) => ListTile(
        title: Text(
          '${shortTime(item['starts_at'])}  ${item['name']} 様 ${item['party_size']}名',
        ),
        subtitle: Text(
          [
            if (item['table_number'] != null) '卓 ${item['table_number']}',
            item['note']?.toString() ?? '',
          ].where((s) => s.isNotEmpty).join(' / '),
        ),
        trailing: DropdownButton<String>(
          value: item['status'] as String?,
          items: [
            for (final s in _statuses.entries)
              DropdownMenuItem(value: s.key, child: Text(s.value)),
          ],
          onChanged: (value) async {
            if (value == null) return;
            final messenger = ScaffoldMessenger.of(context);
            final result = await SaleExtrasApi.updateReservation(
              item['id'] as int,
              value,
            );
            if (result['success'] != true) {
              messenger.showSnackBar(
                SnackBar(content: Text(result['message']?.toString() ?? '')),
              );
            }
            reload();
          },
        ),
      ),
    );
  }
}
