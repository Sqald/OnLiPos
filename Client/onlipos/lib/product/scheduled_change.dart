/// 適用日が決まっている価格・税率の変更。
/// オフラインでも適用日（端末の日付）から新しい価格・税率で会計できるよう、
/// マスタ同期で受け取って端末側でも反映する。
library;

import 'package:onlipos/product/product.dart';

class ScheduledChange {
  final int productId;
  // true なら店舗売価の変更、false なら商品マスタ（定価・税率）の変更
  final bool storePrice;
  final String effectiveOn; // YYYY-MM-DD
  final int? price;
  final int? taxRate;
  final int? taxType;
  final int? eatInPrice;
  final int? eatInTaxRate;

  const ScheduledChange({
    required this.productId,
    required this.storePrice,
    required this.effectiveOn,
    this.price,
    this.taxRate,
    this.taxType,
    this.eatInPrice,
    this.eatInTaxRate,
  });

  factory ScheduledChange.fromMap(Map<String, dynamic> map) => ScheduledChange(
    productId: (map['product_id'] as num).toInt(),
    storePrice: map['store_price'] == true,
    effectiveOn: map['effective_on'] as String,
    price: (map['price'] as num?)?.toInt(),
    taxRate: (map['tax_rate'] as num?)?.toInt(),
    taxType: (map['tax_type'] as num?)?.toInt(),
    eatInPrice: (map['eat_in_price'] as num?)?.toInt(),
    eatInTaxRate: (map['eat_in_tax_rate'] as num?)?.toInt(),
  );

  /// [today]（YYYY-MM-DD）までに適用日を迎えた変更を、古い順に反映した商品を返す
  static Product apply(
    Product product,
    Iterable<ScheduledChange> changes,
    String today,
  ) {
    final due =
        changes
            .where(
              (c) =>
                  c.productId == product.id &&
                  c.effectiveOn.compareTo(today) <= 0,
            )
            .toList()
          ..sort((a, b) => a.effectiveOn.compareTo(b.effectiveOn));

    var result = product;
    for (final c in due) {
      if (c.storePrice) {
        result = result.copyWith(price: c.price);
      } else {
        result = result.copyWith(
          // 店舗売価がある商品では、商品マスタの価格変更は定価だけに反映する
          price: result.hasStorePrice ? null : c.price,
          listPrice: c.price,
          taxRate: c.taxRate,
          taxType: c.taxType,
          eatInPrice: c.eatInPrice,
          eatInTaxRate: c.eatInTaxRate,
        );
      }
    }
    return result;
  }
}
