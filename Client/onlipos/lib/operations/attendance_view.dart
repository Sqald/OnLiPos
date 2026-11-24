// 勤怠の打刻（従業員コード＋PIN）
import 'package:flutter/material.dart';
import 'package:onlipos/operations/common.dart';
import 'package:onlipos/sale/sale_extras_api.dart';

class AttendanceView extends StatefulWidget {
  const AttendanceView({super.key});

  @override
  State<AttendanceView> createState() => _AttendanceViewState();
}

class _AttendanceViewState extends State<AttendanceView> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;

  static const _punches = {
    'clock_in': '出勤',
    'clock_out': '退勤',
    'break_start': '休憩開始',
    'break_end': '休憩終了',
  };

  @override
  void dispose() {
    _code.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _punch(String punch, VoidCallback reload) async {
    setState(() => _busy = true);
    final result = await SaleExtrasApi.punch(
      code: _code.text.trim(),
      pin: _pin.text.trim(),
      punch: punch,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _pin.clear();
    if (result['success'] == true) _code.clear();
    showResult(
      result,
      '${result['employee_name']} さん ${_punches[punch]}を記録しました',
    );
    reload();
  }

  @override
  Widget build(BuildContext context) {
    return ReloadableList(
      title: '勤怠',
      load: SaleExtrasApi.attendances,
      listKey: 'attendances',
      emptyMessage: '勤務中の従業員はいません',
      header: (reload) => Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 160,
              child: TextField(
                controller: _code,
                decoration: const InputDecoration(labelText: '従業員コード'),
              ),
            ),
            SizedBox(
              width: 160,
              child: TextField(
                controller: _pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'PIN'),
              ),
            ),
            for (final entry in _punches.entries)
              ElevatedButton(
                onPressed: _busy ? null : () => _punch(entry.key, reload),
                child: Text(entry.value),
              ),
          ],
        ),
      ),
      itemBuilder: (context, item, reload) => ListTile(
        leading: Icon(item['on_break'] == true ? Icons.coffee : Icons.work),
        title: Text(item['employee_name']?.toString() ?? ''),
        subtitle: Text('出勤 ${shortTime(item['clock_in_at'])}'),
      ),
    );
  }
}
