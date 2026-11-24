// 勤怠の打刻（従業員コード＋PIN）
import 'package:material_ui/material_ui.dart';
import 'package:onlipos/ui/credential_pad.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
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
    if (_code.text.trim().isEmpty || _pin.text.isEmpty) {
      showMessage(context, '従業員番号とPINを入力してください', MessageType.error);
      return;
    }
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

  static const _icons = {
    'clock_in': Icons.login,
    'clock_out': Icons.logout,
    'break_start': Icons.coffee,
    'break_end': Icons.work,
  };

  @override
  Widget build(BuildContext context) {
    return ReloadableList(
      title: '勤怠',
      load: SaleExtrasApi.attendances,
      listKey: 'attendances',
      emptyMessage: 'いま勤務中の人はいません',
      emptyIcon: Icons.people_outline,
      header: (reload) => Container(
        color: AppColors.surface,
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: CredentialPad(
              codeController: _code,
              pinController: _pin,
              keyHeight: 46,
              onSubmit: () {},
              actions: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final entry in _punches.entries)
                    SizedBox(
                      width: 156,
                      child: entry.key.startsWith('clock')
                          ? ElevatedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _punch(entry.key, reload),
                              icon: Icon(_icons[entry.key]),
                              label: Text(entry.value),
                            )
                          : OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _punch(entry.key, reload),
                              icon: Icon(_icons[entry.key]),
                              label: Text(entry.value),
                            ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      itemBuilder: (context, item, reload) => ListTile(
        leading: Icon(item['on_break'] == true ? Icons.coffee : Icons.work),
        title: Text(item['employee_name']?.toString() ?? ''),
        subtitle: Text('出勤 ${shortTime(item['clock_in_at'])}'),
        trailing: StatusBadge(
          item['on_break'] == true ? '休憩中' : '勤務中',
          type: item['on_break'] == true
              ? MessageType.warning
              : MessageType.success,
        ),
      ),
    );
  }
}
