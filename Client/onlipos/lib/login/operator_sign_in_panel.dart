/// 権限が必要な画面を開いたときの、担当者の確認（従業員番号＋PIN）。
/// 権限の有無はサーバーで確認する。
library;

import 'package:flutter/material.dart';
import 'package:onlipos/login/login_api.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/credential_pad.dart';

class OperatorSignInPanel extends StatefulWidget {
  const OperatorSignInPanel({
    super.key,
    required this.icon,
    required this.message,
    required this.permission,
    required this.onAuthenticated,
  });

  final IconData icon;
  final String message;
  final String permission;
  final void Function(int id, String name) onAuthenticated;

  @override
  State<OperatorSignInPanel> createState() => _OperatorSignInPanelState();
}

class _OperatorSignInPanelState extends State<OperatorSignInPanel> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    final pin = _pin.text.trim();
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
    if (result['success'] == true && id is int) {
      widget.onAuthenticated(id, result['employee_name']?.toString() ?? '');
      return;
    }
    _pin.clear();
    setState(() {
      _loading = false;
      _error = result['message']?.toString() ?? '確認できませんでした';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: CredentialPad(
                codeController: _code,
                pinController: _pin,
                loading: _loading,
                error: _error,
                submitLabel: '開く',
                onSubmit: _submit,
                leading: Row(
                  children: [
                    Icon(widget.icon, size: 36, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(fontSize: 16, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
