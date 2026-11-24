/// 画面で共通に使う小さな部品
library;

import 'package:material_ui/material_ui.dart';
import 'package:onlipos/ui/app_theme.dart';

/// 金額を「¥1,234」の形にする
String yen(num? amount) {
  if (amount == null) return '-';
  final digits = amount.round().abs().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return '${amount < 0 ? '-' : ''}¥$digits';
}

enum MessageType { info, success, warning, error }

/// 画面下にお知らせを表示する
void showMessage(
  BuildContext context,
  String text, [
  MessageType type = MessageType.info,
]) {
  final (color, icon) = switch (type) {
    MessageType.success => (AppColors.success, Icons.check_circle),
    MessageType.warning => (AppColors.warning, Icons.warning_amber),
    MessageType.error => (AppColors.danger, Icons.error_outline),
    MessageType.info => (AppColors.ink, Icons.info_outline),
  };
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: color,
        duration: Duration(seconds: type == MessageType.error ? 6 : 4),
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
}

/// はい／いいえの確認。実行する場合だけ true
Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String okLabel = 'はい',
  String cancelLabel = 'やめる',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: danger
              ? ElevatedButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          child: Text(okLabel),
        ),
      ],
    ),
  );
  return result == true;
}

/// 何もないときの案内
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: const Color(0xFFB9C3D2)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: AppColors.secondary,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// 状態を表す小さなラベル
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.text, {super.key, this.type = MessageType.info});

  final String text;
  final MessageType type;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (type) {
      MessageType.success => (AppColors.success, AppColors.successSoft),
      MessageType.warning => (AppColors.warning, AppColors.warningSoft),
      MessageType.error => (AppColors.danger, AppColors.dangerSoft),
      MessageType.info => (AppColors.secondary, const Color(0xFFEEF1F6)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}

/// 白い枠で囲んだ区画（見出し付き）
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.child, this.padding});

  final String? title;
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// 「見出し …… 値」の1行
class LabelValue extends StatelessWidget {
  const LabelValue(
    this.label,
    this.value, {
    super.key,
    this.size = 16,
    this.bold = false,
    this.color,
  });

  final String label;
  final String value;
  final double size;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: size.clamp(14, 18),
                color: AppColors.secondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: size,
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
