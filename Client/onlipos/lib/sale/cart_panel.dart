/// 会計画面（読み取り・一覧）で共通に使う、合計の表示とカートの行。
library;

import 'package:flutter/material.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/common.dart';

/// 合計の下に並べる操作（コード入力・保留・取り消しなど）
typedef CartAction = ({IconData icon, String label, VoidCallback? onTap});

/// 右側の合計とボタン。画面が低いときも合計が必ず見えるように、操作を印だけの表示に切り替える
class CartSummaryPanel extends StatelessWidget {
  const CartSummaryPanel({
    super.key,
    required this.itemCount,
    required this.total,
    required this.tax,
    this.promotionDiscount = 0,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    this.actions = const [],
  });

  final int itemCount;
  final int total;
  final int tax;
  final int promotionDiscount;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback? onPrimary;
  final List<CartAction> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < 460;
        return Container(
          color: AppColors.surface,
          padding: EdgeInsets.all(compact ? 10 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LabelValue(
                        '点数',
                        '$itemCount 点',
                        size: compact ? 17 : 22,
                        bold: true,
                      ),
                      if (!compact) ...[
                        const Divider(height: 20),
                        const Text(
                          '合計（税込）',
                          style: TextStyle(
                            fontSize: 17,
                            color: AppColors.secondary,
                          ),
                        ),
                      ],
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          yen(total),
                          style: TextStyle(
                            fontSize: compact ? 40 : 54,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      if (promotionDiscount > 0)
                        LabelValue(
                          'まとめ買い割引',
                          yen(-promotionDiscount),
                          color: AppColors.danger,
                          bold: true,
                        ),
                      if (tax > 0) LabelValue('うち消費税', yen(tax)),
                    ],
                  ),
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final action in actions)
                      compact
                          ? IconButton.outlined(
                              onPressed: action.onTap,
                              tooltip: action.label,
                              icon: Icon(action.icon),
                            )
                          : OutlinedButton.icon(
                              onPressed: action.onTap,
                              icon: Icon(action.icon, size: 20),
                              label: Text(action.label),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(64, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                              ),
                            ),
                  ],
                ),
              ],
              SizedBox(height: compact ? 8 : 12),
              SizedBox(
                height: compact ? 60 : 76,
                child: ElevatedButton.icon(
                  onPressed: onPrimary,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: Icon(primaryIcon, size: 28),
                  label: FittedBox(
                    child: Text(
                      primaryLabel,
                      style: const TextStyle(fontSize: 26),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 数量の増減（押しやすい大きさのボタン）
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.onMinus,
    required this.onPlus,
    this.removeOnMinus = false,
  });

  final int quantity;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  /// 減らすと行が消えるとき、ゴミ箱の印にする
  final bool removeOnMinus;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String tooltip, VoidCallback? onTap) =>
        IconButton.outlined(
          onPressed: onTap,
          tooltip: tooltip,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            side: const BorderSide(color: Color(0xFFB9C3D2)),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          removeOnMinus ? Icons.delete_outline : Icons.remove,
          removeOnMinus ? '取り消す' : '1つ減らす',
          onMinus,
        ),
        SizedBox(
          width: 46,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        button(Icons.add, '1つ増やす', onPlus),
      ],
    );
  }
}
