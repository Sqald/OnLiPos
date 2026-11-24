/// 指で押しやすい数字入力（テンキー）。つなげたキーボードやバーコードリーダーからも入力できる。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onlipos/ui/app_theme.dart';

class NumPad extends StatelessWidget {
  const NumPad({
    super.key,
    required this.controller,
    this.maxLength = 9,
    this.keyHeight = 58,
    this.showDoubleZero = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final int maxLength;
  final double keyHeight;

  /// 金額の入力では「00」を出す（番号の入力では「消す」だけ）
  final bool showDoubleZero;
  final VoidCallback? onChanged;

  // 選択中の文字があれば置き換える（最初に入っている金額を打ち直せるように）
  void _type(String text) {
    final selection = controller.selection;
    final selected =
        selection.isValid &&
        !selection.isCollapsed &&
        controller.text.isNotEmpty;
    var next = selected ? text : controller.text + text;
    if (next.length > maxLength) return;
    if (showDoubleZero) next = next.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    _set(next);
  }

  void _set(String text) {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    HapticFeedback.selectionClick();
    onChanged?.call();
  }

  void _backspace() {
    final text = controller.text;
    if (text.isEmpty) return;
    _set(text.substring(0, text.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    Widget key(
      String label, {
      VoidCallback? onTap,
      Widget? child,
      Color? color,
    }) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          height: keyHeight,
          child: Material(
            color: color ?? AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: AppColors.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              // フォーカスを奪うと、つないだキーボードの入力先が変わってしまう
              canRequestFocus: false,
              onTap: onTap ?? () => _type(label),
              child: Center(
                child:
                    child ??
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['7', '8', '9'],
          ['4', '5', '6'],
          ['1', '2', '3'],
        ])
          Row(children: [for (final n in row) key(n)]),
        Row(
          children: [
            showDoubleZero
                ? key('00')
                : key(
                    '全部消す',
                    onTap: () => _set(''),
                    color: const Color(0xFFEEF1F6),
                    child: const Text('クリア', style: TextStyle(fontSize: 16)),
                  ),
            key('0'),
            key(
              '1文字消す',
              onTap: _backspace,
              color: const Color(0xFFEEF1F6),
              child: const Icon(
                Icons.backspace_outlined,
                semanticLabel: '1文字消す',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
