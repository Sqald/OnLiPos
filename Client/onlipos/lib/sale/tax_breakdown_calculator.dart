/// 税率別内訳の計算（サーバーの TaxCalculator と同一仕様）。
/// 明細を（税率, 税区分）ごとにまとめ、インボイス制度の
/// 「1レシートにつき税率ごとに端数処理1回」でレシート印字用の内訳を作る。
///
/// tax_type: 0 = 内税（既定）, 1 = 外税, 2 = 非課税
class TaxBreakdownCalculator {
  /// rounding: 'round_down'(切捨て) / 'round_half_up'(四捨五入) / 'round_up'(切上げ)
  static List<Map<String, int>> fromDetails(
    List<Map<String, dynamic>> details, {
    String rounding = 'round_down',
  }) {
    // (税率, 税区分) -> 金額合計
    final groups = <String, int>{};
    for (final d in details) {
      final rate = (d['tax_rate'] as num?)?.toInt() ?? 10;
      final taxType = (d['tax_type'] as num?)?.toInt() ?? 0;
      final sub = (d['subtotal'] as num?)?.toInt() ?? 0;
      final key = '$rate:$taxType';
      groups[key] = (groups[key] ?? 0) + sub;
    }

    final keys = groups.keys.toList()
      ..sort((a, b) {
        final ra = int.parse(a.split(':')[0]);
        final rb = int.parse(b.split(':')[0]);
        return ra.compareTo(rb);
      });

    return keys.map((key) {
      final parts = key.split(':');
      final rate = int.parse(parts[0]);
      final taxType = int.parse(parts[1]);
      final amount = groups[key]!;

      switch (taxType) {
        case 1: // 外税: amount は税抜
          final tax = _round(amount * rate / 100, rounding);
          return {
            'tax_rate': rate,
            'tax_type': taxType,
            'taxable_amount': amount + tax,
            'amount_ex_tax': amount,
            'tax_amount': tax,
          };
        case 2: // 非課税
          return {
            'tax_rate': rate,
            'tax_type': taxType,
            'taxable_amount': amount,
            'amount_ex_tax': amount,
            'tax_amount': 0,
          };
        default: // 内税: amount は税込
          final tax = _round(amount * rate / (100 + rate), rounding);
          return {
            'tax_rate': rate,
            'tax_type': taxType,
            'taxable_amount': amount,
            'amount_ex_tax': amount - tax,
            'tax_amount': tax,
          };
      }
    }).toList();
  }

  static int _round(double value, String rounding) {
    switch (rounding) {
      case 'round_half_up':
        return value.round();
      case 'round_up':
        return value.ceil();
      default:
        return value.floor();
    }
  }
}
