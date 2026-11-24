/// 従業員番号とPINの入力（テンキー付き）。ログイン・担当者認証・勤怠で共通に使う。
library;

import 'package:flutter/material.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/num_pad.dart';

class CredentialPad extends StatefulWidget {
  const CredentialPad({
    super.key,
    required this.codeController,
    this.pinController,
    required this.onSubmit,
    this.submitLabel = '確認',
    this.loading = false,
    this.error,
    this.codeLabel = '従業員番号',
    this.leading,
    this.actions,
    this.keyHeight = 58,
  });

  final TextEditingController codeController;

  /// null なら番号だけを入力する
  final TextEditingController? pinController;
  final VoidCallback onSubmit;
  final String submitLabel;
  final bool loading;
  final String? error;
  final String codeLabel;

  /// 入力欄の上に置くもの（営業日など）
  final Widget? leading;

  /// 決定ボタンの代わりに置くもの（出勤・退勤など、複数のボタン）
  final Widget? actions;
  final double keyHeight;

  @override
  State<CredentialPad> createState() => _CredentialPadState();
}

class _CredentialPadState extends State<CredentialPad> {
  final _codeFocus = FocusNode();
  final _pinFocus = FocusNode();

  // 番号に英字を使う場合だけ、画面のキーボードを出す
  bool _letters = false;

  @override
  void initState() {
    super.initState();
    _codeFocus.addListener(_refresh);
    _pinFocus.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _codeFocus.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  bool get _pinActive => widget.pinController != null && _pinFocus.hasFocus;

  void _next() {
    if (widget.pinController != null && !_pinActive) {
      _pinFocus.requestFocus();
    } else if (!widget.loading && widget.actions == null) {
      widget.onSubmit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.leading != null) ...[
          widget.leading!,
          const SizedBox(height: 16),
        ],
        TextField(
          controller: widget.codeController,
          focusNode: _codeFocus,
          autofocus: true,
          keyboardType: _letters ? TextInputType.text : TextInputType.none,
          textInputAction: TextInputAction.next,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            labelText: widget.codeLabel,
            prefixIcon: const Icon(Icons.person),
            suffixIcon: IconButton(
              tooltip: _letters ? 'テンキーで入力' : '文字のキーボードで入力',
              icon: Icon(_letters ? Icons.dialpad : Icons.keyboard),
              onPressed: () {
                setState(() => _letters = !_letters);
                _codeFocus.unfocus();
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _codeFocus.requestFocus(),
                );
              },
            ),
          ),
          onSubmitted: (_) => _next(),
        ),
        if (widget.pinController != null) ...[
          const SizedBox(height: 14),
          TextField(
            controller: widget.pinController,
            focusNode: _pinFocus,
            obscureText: true,
            keyboardType: TextInputType.none,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              labelText: 'PIN（暗証番号）',
              prefixIcon: Icon(Icons.lock),
            ),
            onSubmitted: (_) => _next(),
          ),
        ],
        if (widget.error != null && widget.error!.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        widget.actions ??
            SizedBox(
              height: 58,
              child: ElevatedButton(
                onPressed: widget.loading ? null : widget.onSubmit,
                child: widget.loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : Text(
                        widget.submitLabel,
                        style: const TextStyle(fontSize: 20),
                      ),
              ),
            ),
      ],
    );
    final pad = NumPad(
      controller: _pinActive ? widget.pinController! : widget.codeController,
      maxLength: _pinActive ? 6 : 12,
      keyHeight: widget.keyHeight,
    );

    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 520) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [fields, const SizedBox(height: 16), pad],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: fields),
            const SizedBox(width: 24),
            SizedBox(width: 264, child: pad),
          ],
        );
      },
    );
  }
}
