/// レジの現金を数える画面（開設・点検・精算）で共通に使う、金種ごとの枚数の入力。
/// 左に合計、中央に枚数の入力欄、右にテンキーを置く。
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/num_pad.dart';

class DenominationForm extends StatefulWidget {
  const DenominationForm({
    super.key,
    required this.controllers,
    required this.totalLabel,
    required this.total,
    required this.submitLabel,
    required this.onSubmit,
    this.loading = false,
    this.danger = false,
    this.details = const [],
  });

  /// 金種（円）ごとの入力欄
  final Map<int, TextEditingController> controllers;
  final String totalLabel;
  final int total;
  final String submitLabel;
  final VoidCallback onSubmit;
  final bool loading;

  /// 取り消しにくい操作（精算）は赤いボタンにする
  final bool danger;

  /// 合計の下に表示する内容（担当者・想定額・差など）
  final List<Widget> details;

  @override
  State<DenominationForm> createState() => _DenominationFormState();
}

class _DenominationFormState extends State<DenominationForm> {
  late final Map<int, FocusNode> _focus = {
    for (final d in widget.controllers.keys) d: FocusNode(),
  };
  late int _active = widget.controllers.keys.first;

  @override
  void initState() {
    super.initState();
    _focus.forEach((denomination, node) {
      node.addListener(() {
        if (node.hasFocus && mounted) setState(() => _active = denomination);
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus[_active]!.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  // 次の金種へ進む（最後まで行ったら何もしない）
  void _next() {
    final keys = widget.controllers.keys.toList();
    final i = keys.indexOf(_active) + 1;
    if (i < keys.length) _focus[keys[i]]!.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final withPad = box.maxWidth >= 900;
        final wide = box.maxWidth >= 640;
        final summary = _summary(compact: !wide);
        final fields = _fields(columns: box.maxWidth >= 1120 ? 2 : 1);
        if (!wide) {
          return Column(
            children: [
              summary,
              Expanded(child: fields),
              Padding(padding: const EdgeInsets.all(12), child: _button()),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: withPad ? 320 : 280,
              child: Container(
                color: AppColors.surface,
                child: Column(
                  children: [
                    Expanded(child: SingleChildScrollView(child: summary)),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _button(),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: fields),
            if (withPad)
              Container(
                width: 280,
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Text(
                          '${yen(_active)} の枚数',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        NumPad(
                          controller: widget.controllers[_active]!,
                          maxLength: 4,
                        ),
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _next,
                              child: const Text('次の金種へ'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _button() => SizedBox(
    width: double.infinity,
    height: 64,
    child: ElevatedButton(
      onPressed: widget.loading ? null : widget.onSubmit,
      style: widget.danger
          ? ElevatedButton.styleFrom(backgroundColor: AppColors.danger)
          : null,
      child: widget.loading
          ? const CircularProgressIndicator()
          : Text(widget.submitLabel, style: const TextStyle(fontSize: 20)),
    ),
  );

  Widget _summary({required bool compact}) => Padding(
    padding: EdgeInsets.all(compact ? 14 : 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.totalLabel,
          style: const TextStyle(fontSize: 16, color: AppColors.secondary),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            yen(widget.total),
            style: TextStyle(
              fontSize: compact ? 32 : 44,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...widget.details,
      ],
    ),
  );

  Widget _fields({required int columns}) {
    final entries = widget.controllers.entries.toList();
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisExtent: 70,
        crossAxisSpacing: 14,
        mainAxisSpacing: 6,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final denomination = entries[i].key;
        final controller = entries[i].value;
        final count = int.tryParse(controller.text) ?? 0;
        return Row(
          children: [
            SizedBox(
              width: 84,
              child: Text(
                yen(denomination),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 130,
              child: TextField(
                controller: controller,
                focusNode: _focus[denomination],
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.right,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _next(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  suffixText: '枚',
                  hintText: '0',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                count == 0 ? '' : yen(denomination * count),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 16,
                  color: AppColors.secondary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
