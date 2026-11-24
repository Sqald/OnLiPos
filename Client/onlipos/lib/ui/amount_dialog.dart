/// 数字を入力するダイアログ（テンキー付き）。金額・重さ・商品コードの入力に使う。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/num_pad.dart';

/// 入力された文字を返す。やめた場合は null
Future<String?> showNumberDialog(
  BuildContext context, {
  required String title,
  String? message,
  String initial = '',
  String prefix = '',
  String suffix = '',
  String okLabel = '決定',
  int maxLength = 9,
  bool allowLetters = false,

  /// 入力できる内容でなければ、その理由を返す
  String? Function(String value)? validate,

  /// 入力に応じて表示する文（金額の計算結果など）
  String Function(String value)? preview,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NumberDialog(
      title: title,
      message: message,
      initial: initial,
      prefix: prefix,
      suffix: suffix,
      okLabel: okLabel,
      maxLength: maxLength,
      allowLetters: allowLetters,
      validate: validate,
      preview: preview,
    ),
  );
}

/// 金額の入力。1円以上・[max] 以下だけ受け付ける
Future<int?> showAmountDialog(
  BuildContext context, {
  required String title,
  required int initial,
  required int max,
  String? message,
}) async {
  final text = await showNumberDialog(
    context,
    title: title,
    message: message ?? '${yen(max)} まで入力できます',
    initial: '$initial',
    prefix: '¥ ',
    validate: (value) {
      final amount = int.tryParse(value) ?? 0;
      if (amount <= 0) return '金額を入力してください';
      if (amount > max) return '${yen(max)} 以下で入力してください';
      return null;
    },
  );
  return text == null ? null : int.parse(text);
}

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({
    required this.title,
    this.message,
    required this.initial,
    required this.prefix,
    required this.suffix,
    required this.okLabel,
    required this.maxLength,
    required this.allowLetters,
    this.validate,
    this.preview,
  });

  final String title;
  final String? message;
  final String initial;
  final String prefix;
  final String suffix;
  final String okLabel;
  final int maxLength;
  final bool allowLetters;
  final String? Function(String value)? validate;
  final String Function(String value)? preview;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  // 最初の値は選択状態にし、打ち始めると置き換わるようにする
  late final _controller = TextEditingController.fromValue(
    TextEditingValue(
      text: widget.initial,
      selection: TextSelection(
        baseOffset: 0,
        extentOffset: widget.initial.length,
      ),
    ),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    final error = widget.validate?.call(value);
    if (error != null || value.isEmpty) {
      setState(() => _error = error ?? '入力してください');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final short = MediaQuery.sizeOf(context).height < 560;
    final field = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              widget.message!,
              style: const TextStyle(fontSize: 15, color: AppColors.secondary),
            ),
          ),
        TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: widget.allowLetters
              ? TextInputType.text
              : TextInputType.none,
          inputFormatters: widget.allowLetters
              ? null
              : [FilteringTextInputFormatter.digitsOnly],
          textAlign: widget.allowLetters ? TextAlign.left : TextAlign.right,
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            prefixText: widget.prefix,
            suffixText: widget.suffix,
            errorText: _error,
          ),
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _submit(),
        ),
        if (widget.preview != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              widget.preview!(_controller.text),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
    final pad = NumPad(
      controller: _controller,
      maxLength: widget.maxLength,
      keyHeight: short ? 42 : 52,
      onChanged: () => setState(() => _error = null),
    );
    final buttons = Wrap(
      alignment: WrapAlignment.end,
      spacing: 10,
      runSpacing: 10,
      children: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('やめる'),
        ),
        ElevatedButton(onPressed: _submit, child: Text(widget.okLabel)),
      ],
    );
    return Dialog(
      insetPadding: EdgeInsets.all(short ? 6 : 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: short ? 660 : 390),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(short ? 16 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              if (short)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [field, const SizedBox(height: 14), buttons],
                      ),
                    ),
                    const SizedBox(width: 20),
                    SizedBox(width: 250, child: pad),
                  ],
                )
              else ...[
                field,
                const SizedBox(height: 8),
                pad,
                const SizedBox(height: 14),
                buttons,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
