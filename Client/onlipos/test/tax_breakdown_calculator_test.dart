import 'package:flutter_test/flutter_test.dart';
import 'package:onlipos/sale/tax_breakdown_calculator.dart';

void main() {
  group('TaxBreakdownCalculator', () {
    test('税率混在の明細を税率ごとに1回だけ端数処理して集計する', () {
      final details = [
        {'subtotal': 1998, 'tax_rate': 8},
        {'subtotal': 999, 'tax_rate': 10},
      ];
      final result = TaxBreakdownCalculator.fromDetails(details);

      expect(result.length, 2);
      // 8%: 1998 × 8/108 = 148.0 → 148
      expect(result[0]['tax_rate'], 8);
      expect(result[0]['taxable_amount'], 1998);
      expect(result[0]['tax_amount'], 148);
      // 10%: 999 × 10/110 = 90.8 → 切捨て 90
      expect(result[1]['tax_rate'], 10);
      expect(result[1]['taxable_amount'], 999);
      expect(result[1]['tax_amount'], 90);
    });

    test('四捨五入・切上げの端数処理方式', () {
      final details = [
        {'subtotal': 999, 'tax_rate': 10},
      ];
      final halfUp = TaxBreakdownCalculator.fromDetails(
        details,
        rounding: 'round_half_up',
      );
      expect(halfUp[0]['tax_amount'], 91); // 90.8 → 91

      final up = TaxBreakdownCalculator.fromDetails(
        details,
        rounding: 'round_up',
      );
      expect(up[0]['tax_amount'], 91);
    });

    test('外税は税抜合計に税額を加算した税込対価を返す', () {
      final details = [
        {'subtotal': 1000, 'tax_rate': 10, 'tax_type': 1},
      ];
      final result = TaxBreakdownCalculator.fromDetails(details);
      expect(result[0]['amount_ex_tax'], 1000);
      expect(result[0]['tax_amount'], 100);
      expect(result[0]['taxable_amount'], 1100);
    });

    test('非課税は税額0', () {
      final details = [
        {'subtotal': 500, 'tax_rate': 0, 'tax_type': 2},
      ];
      final result = TaxBreakdownCalculator.fromDetails(details);
      expect(result[0]['tax_amount'], 0);
      expect(result[0]['taxable_amount'], 500);
    });

    test('同一税率の明細は合算してから端数処理する', () {
      final details = [
        {'subtotal': 999, 'tax_rate': 10},
        {'subtotal': 999, 'tax_rate': 10},
      ];
      final result = TaxBreakdownCalculator.fromDetails(details);
      // 1998 × 10/110 = 181.6 → 181（明細ごとなら 90+90=180）
      expect(result.length, 1);
      expect(result[0]['tax_amount'], 181);
    });
  });
}
