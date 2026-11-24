/// 決済端末との連携の窓口。
/// 実機との連動は決済事業者との契約・SDKが必要なため、現在は「端末で承認を確認して取引番号を控える」
/// 手動方式（[ManualPaymentTerminal]）のみ。連動する場合はこのクラスを実装して差し替える。
/// カード番号などの決済情報は OnLiPos では扱わない（非保持）。
library;

import 'package:flutter/material.dart';
import 'package:onlipos/ui/common.dart';

class TerminalResult {
  /// 承認番号・取引番号（返金時の照合に使う）
  final String? reference;
  final String provider;

  const TerminalResult({this.reference, required this.provider});
}

abstract class PaymentTerminal {
  /// [amount] 円の決済を行う。取り消された場合は null
  Future<TerminalResult?> pay(
    BuildContext context, {
    required String methodLabel,
    required int amount,
  });

  static PaymentTerminal current = const ManualPaymentTerminal();
}

class ManualPaymentTerminal implements PaymentTerminal {
  const ManualPaymentTerminal();

  @override
  Future<TerminalResult?> pay(
    BuildContext context, {
    required String methodLabel,
    required int amount,
  }) {
    return showDialog<TerminalResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ManualTerminalDialog(label: methodLabel, amount: amount),
    );
  }
}

class _ManualTerminalDialog extends StatefulWidget {
  const _ManualTerminalDialog({required this.label, required this.amount});

  final String label;
  final int amount;

  @override
  State<_ManualTerminalDialog> createState() => _ManualTerminalDialogState();
}

class _ManualTerminalDialogState extends State<_ManualTerminalDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() => Navigator.of(context).pop(
    TerminalResult(
      reference: _controller.text.trim().isEmpty
          ? null
          : _controller.text.trim(),
      provider: 'manual',
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.label} ${yen(widget.amount)}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('決済端末に ${yen(widget.amount)} を入力し、支払いが完了したことを確認してください。'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: '取引番号（なくても可）',
              helperText: 'カード番号は入力しないでください',
            ),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('やめる'),
        ),
        ElevatedButton(onPressed: _confirm, child: const Text('支払い完了を確認した')),
      ],
    );
  }
}
