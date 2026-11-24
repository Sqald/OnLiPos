/// 操作ごとの担当者認証ダイアログ。
/// 担当者コード＋PINをサーバーで検証し、同時に操作に必要な権限（[permission]）を
/// 担当者本人が持っているかをサーバー側で確認する。
/// 業務開始時にログインした担当者と、実際に操作する担当者が異なる場合に備え、
/// レジ金チェック・精算などの操作の直前に呼び出す。
library;

import 'package:material_ui/material_ui.dart';
import 'package:onlipos/ui/credential_pad.dart';
import 'package:onlipos/api/pos_api_client.dart';
import 'package:onlipos/login/login_api.dart';

/// 認証に成功した担当者を返す。キャンセル時は null。
/// [allowOffline] の場合、通信できないときに認証なしで続行できる（id は 0。サーバーでは要確認として記録される）。
Future<({int id, String name})?> showEmployeeAuthDialog(
  BuildContext context, {
  required String title,
  required String permission,
  bool allowOffline = false,
}) {
  return showDialog<({int id, String name})>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EmployeeAuthDialog(
      title: title,
      permission: permission,
      allowOffline: allowOffline,
    ),
  );
}

class _EmployeeAuthDialog extends StatefulWidget {
  const _EmployeeAuthDialog({
    required this.title,
    required this.permission,
    required this.allowOffline,
  });

  final String title;
  final String permission;
  final bool allowOffline;

  @override
  State<_EmployeeAuthDialog> createState() => _EmployeeAuthDialogState();
}

class _EmployeeAuthDialogState extends State<_EmployeeAuthDialog> {
  final _codeController = TextEditingController();
  final _pinController = TextEditingController();
  bool _loading = false;
  bool _offline = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  // 担当者コード・PIN・必要権限をサーバーで検証し、成功したら担当者を返して閉じる
  Future<void> _submit() async {
    final code = _codeController.text.trim();
    final pin = _pinController.text.trim();
    if (code.isEmpty || pin.isEmpty) {
      setState(() => _error = '従業員番号とPINを入力してください');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await LoginApi.verifyEmployee(
      code: code,
      pin: pin,
      permission: widget.permission,
    );
    if (!mounted) return;

    final id = result['employee_id'];
    final name = result['employee_name'];
    if (result['success'] == true && id is int && name is String) {
      Navigator.of(context).pop((id: id, name: name));
      return;
    }

    _pinController.clear();
    setState(() {
      _loading = false;
      _offline = const {
        PosApiClient.offlineMessage,
        PosApiClient.timeoutMessage,
      }.contains(result['message']);
      _error = result['message']?.toString() ?? '認証に失敗しました';
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final short = size.height < 520;
    return Dialog(
      insetPadding: EdgeInsets.all(short ? 6 : 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: size.width >= 640 ? 660 : 400),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            short ? 10 : 20,
            24,
            short ? 10 : 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(64, 44),
                    ),
                    child: const Text('やめる'),
                  ),
                ],
              ),
              SizedBox(height: short ? 8 : 18),
              CredentialPad(
                codeController: _codeController,
                pinController: _pinController,
                loading: _loading,
                error: _error,
                submitLabel: '確認する',
                keyHeight: short ? 46 : 54,
                onSubmit: _submit,
              ),
              if (widget.allowOffline && _offline) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).pop((id: 0, name: '')),
                  child: const Text('確認せずに続ける（あとで確認が必要な会計になります）'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
