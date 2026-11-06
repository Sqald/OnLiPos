/// 操作ごとの担当者認証ダイアログ。
/// 担当者コード＋PINをサーバーで検証し、同時に操作に必要な権限（[permission]）を
/// 担当者本人が持っているかをサーバー側で確認する。
/// 業務開始時にログインした担当者と、実際に操作する担当者が異なる場合に備え、
/// レジ金チェック・精算などの操作の直前に呼び出す。
library;

import 'package:flutter/material.dart';
import 'package:onlipos/login/login_api.dart';

/// 認証に成功した担当者を返す。キャンセル時は null。
Future<({int id, String name})?> showEmployeeAuthDialog(
  BuildContext context, {
  required String title,
  required String permission,
}) {
  return showDialog<({int id, String name})>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EmployeeAuthDialog(title: title, permission: permission),
  );
}

class _EmployeeAuthDialog extends StatefulWidget {
  const _EmployeeAuthDialog({required this.title, required this.permission});

  final String title;
  final String permission;

  @override
  State<_EmployeeAuthDialog> createState() => _EmployeeAuthDialogState();
}

class _EmployeeAuthDialogState extends State<_EmployeeAuthDialog> {
  final _codeController = TextEditingController();
  final _pinController = TextEditingController();
  bool _loading = false;
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
      setState(() => _error = '担当者コードとPINを入力してください');
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

    setState(() {
      _loading = false;
      _error = result['message']?.toString() ?? '認証に失敗しました';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _codeController,
              autofocus: true,
              decoration: const InputDecoration(labelText: '担当者コード'),
              textInputAction: TextInputAction.next,
            ),
            TextField(
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'PIN'),
              onSubmitted: (_) => _loading ? null : _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('認証'),
        ),
      ],
    );
  }
}
