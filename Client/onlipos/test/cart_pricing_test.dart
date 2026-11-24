import 'package:flutter_test/flutter_test.dart';
import 'package:onlipos/api/pos_api_client.dart';
import 'package:onlipos/product/product.dart';
import 'package:onlipos/product/scheduled_change.dart';
import 'package:onlipos/sale/cart_pricing.dart';
import 'package:onlipos/sale/promotion.dart';
import 'package:onlipos/sale/sale_item.dart';

void main() {
  final bento = Product(
    id: 1,
    code: 'F',
    name: '弁当',
    price: 1080,
    taxRate: 8,
    eatInTaxRate: 10,
    eatInPrice: 1100,
    minAge: 20,
    categoryId: 5,
  );
  final tea = Product(id: 2, code: 'T', name: '茶', price: 150, taxRate: 8);
  final exclusive = Product(
    id: 3,
    code: 'X',
    name: '外税',
    price: 101,
    taxType: TaxType.exclusive,
  );

  test('店内飲食で価格と税率が変わる', () {
    final quote = const CartPricing().quote([
      ScannedItem(product: bento),
      ScannedItem(product: bento, eatIn: true),
    ]);
    expect(quote.total, 2180);
    expect(quote.taxBreakdown.map((b) => b['tax_rate']), [8, 10]);
    expect(quote.details[1]['service_type'], 'eat_in');
    expect(quote.requiredAge, 20);
  });

  test('外税は税率ごとに1回だけ端数処理する', () {
    final quote = const CartPricing().quote([
      ScannedItem(product: exclusive, quantity: 3),
      ScannedItem(product: exclusive),
    ]);
    expect(quote.total, 404 + 40);
    expect(quote.tax, 40);
  });

  test('タイムセールは時間内だけ適用し、手動の価格変更が優先', () {
    final pricing = CartPricing(
      promotions: [
        const Promotion(
          id: 1,
          name: '夕市',
          kind: 'time_sale',
          percentOff: 20,
          categoryId: 5,
          startMinute: 17 * 60,
          endMinute: 19 * 60,
        ),
      ],
    );
    final item = ScannedItem(product: bento);
    expect(pricing.quote([item], at: DateTime(2026, 12, 1, 18)).total, 864);
    expect(pricing.quote([item], at: DateTime(2026, 12, 1, 20)).total, 1080);
    item.overridePrice = 1000;
    final quote = pricing.quote([item], at: DateTime(2026, 12, 1, 18));
    expect(quote.total, 1000);
    expect(quote.needsDiscountApproval, isTrue);
  });

  test('よりどり・まとめ買い割引（サーバーのテストと同じ値）', () {
    final pricing = CartPricing(
      promotions: [
        const Promotion(
          id: 1,
          name: '2点1100円',
          kind: 'set_price',
          setQuantity: 2,
          fixedPrice: 1100,
          productIds: [1, 2],
        ),
      ],
    );
    final quote = pricing.quote([
      ScannedItem(product: bento),
      ScannedItem(product: tea, quantity: 2),
    ]);
    expect(quote.promotionDiscount, 130);
    expect(quote.total, 1250);
    expect(quote.needsDiscountApproval, isFalse);
  });

  test('小計割引は明細へ按分し、クーポンは承認不要', () {
    final items = [ScannedItem(product: tea, quantity: 3)];
    final manual = const CartPricing().quote(
      items,
      orderDiscount: const OrderDiscount(
        type: 'percent',
        value: 10,
        reason: 'x',
      ),
    );
    expect(manual.total, 405);
    expect(manual.needsDiscountApproval, isTrue);
    final coupon = const CartPricing().quote(
      items,
      orderDiscount: const OrderDiscount(
        type: 'amount',
        value: 1000,
        reason: 'x',
        couponCode: 'C',
      ),
    );
    expect(coupon.total, 0);
    expect(coupon.needsDiscountApproval, isFalse);
  });

  test('セット商品は1行で送り、税は構成商品ごとに計算する', () {
    final bundle = ScannedItem(
      product: Product(id: -1, code: 'SET', name: 'セット', price: 1000),
      bundleCode: 'SET',
      bundleName: 'セット',
      components: const [
        BundleComponent(weight: 1080, taxRate: 8),
        BundleComponent(weight: 150, taxRate: 10),
      ],
      quantity: 2,
    );
    final quote = const CartPricing().quote([bundle]);
    expect(quote.details, [
      {
        'bundle_code': 'SET',
        'product_name': 'セット',
        'quantity': 2,
        'unit_price': 1000,
        'subtotal': 2000,
      },
    ]);
    expect(quote.taxBreakdown.map((b) => b['taxable_amount']), [1756, 244]);
  });

  test('カートはJSONにして他の端末へ渡しても同じ金額になる', () {
    final item = ScannedItem(
      product: bento,
      quantity: 2,
      eatIn: true,
      options: const [OptionItem(id: 9, name: '卵', price: 50)],
    );
    final copy = ScannedItem.fromJson(item.toJson());
    expect(copy.subtotal, 2300);
    expect(copy.product.eatInTaxRate, 10);
    expect(const CartPricing().quote([copy]).details.first['options'], [9]);
  });

  test('予約変更は適用日から反映し、店舗売価のある商品は定価だけ変わる', () {
    final changes = [
      ScheduledChange.fromMap({
        'product_id': 1,
        'store_price': false,
        'effective_on': '2027-04-01',
        'price': 1010,
        'tax_rate': 1,
      }),
    ];
    final before = ScheduledChange.apply(bento, changes, '2027-03-31');
    final after = ScheduledChange.apply(bento, changes, '2027-04-01');
    expect([before.price, before.taxRate], [1080, 8]);
    expect([after.price, after.taxRate, after.eatInTaxRate], [1010, 1, 10]);

    final store = bento.copyWith(price: 900);
    final storeAfter = ScheduledChange.apply(store, changes, '2027-04-01');
    expect([storeAfter.price, storeAfter.listPrice], [900, 1010]);
  });

  test('承認トークンは期限内のものだけを送る', () {
    OperatorApprovals.clear();
    OperatorApprovals.addFromResponse({
      'success': true,
      'employee_id': 1,
      'approval_token': 'a',
      'approval_permission': 'refund',
      'approval_expires_at': DateTime.now()
          .add(const Duration(minutes: 1))
          .toIso8601String(),
    });
    OperatorApprovals.addFromResponse({
      'success': true,
      'employee_id': 2,
      'approval_token': 'b',
      'approval_permission': 'refund',
      'approval_expires_at': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
    });
    expect(OperatorApprovals.headerValue(), 'a');
    OperatorApprovals.clear('refund');
    expect(OperatorApprovals.has('refund'), isFalse);
  });
}
