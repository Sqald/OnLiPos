/// 全画面共通のヘッダー。左に「戻る」、中央寄りに画面名（と補足）、右に操作を置く。
library;

import 'package:material_ui/material_ui.dart';
import 'package:onlipos/ui/app_theme.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader(
    this.title, {
    super.key,
    this.subtitle,
    this.actions = const [],
    this.showBack,
    this.onBack,
    this.bottom,
  });

  final String title;

  /// 担当者・卓番などの補足
  final String? subtitle;
  final List<Widget> actions;

  /// 「戻る」を出すか（指定しなければ、戻れる画面でだけ出す）
  final bool? showBack;
  final VoidCallback? onBack;
  final PreferredSizeWidget? bottom;

  static const _height = 64.0;

  @override
  Size get preferredSize =>
      Size.fromHeight(_height + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final canBack =
        showBack ??
        (onBack != null || (ModalRoute.of(context)?.canPop ?? false));
    return AppBar(
      toolbarHeight: _height,
      automaticallyImplyLeading: false,
      leadingWidth: canBack ? 118 : 0,
      leading: canBack
          ? Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: onBack ?? () => Navigator.maybePop(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(100, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: const Icon(Icons.arrow_back, size: 20),
                  label: const Text('戻る'),
                ),
              ),
            )
          : null,
      titleSpacing: 16,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: const TextStyle(fontSize: 13, color: AppColors.secondary),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      actions: [...actions, const SizedBox(width: 12)],
      bottom: bottom,
    );
  }
}
