// 会計中のカートに積まれた1商品分のデータモデル（ScannedItem）を定義する。
// セット商品展開・手動値引きに対応する。
library;

import 'package:onlipos/product/product.dart';

/// スキャン／選択した商品1件分（数量・値引きなどを含む）。
class ScannedItem {
  final Product product;
  // セット商品から展開された場合のセットコード
  final String? bundleCode;
  final String? bundleName;
  int quantity;
  // null の場合は product.price を使用。値引き・賞味期限値変更などで上書きする
  int? overridePrice;
  // 値引き理由（手動値引き時のみ）
  String? discountReason;
  // 量り売り（計量）商品の重量(g)。product.soldByWeight の商品のみ設定される。
  // 設定時は price を100gあたりの単価として重量から金額を算出する
  int? weightGrams;

  ScannedItem({
    required this.product,
    this.bundleCode,
    this.bundleName,
    this.quantity = 1,
    this.overridePrice,
    this.discountReason,
    this.weightGrams,
  });

  int get price => overridePrice ?? product.price;

  // カート内で独立に扱えるようディープコピーを作成する
  ScannedItem copy() => ScannedItem(
    product: product,
    bundleCode: bundleCode,
    bundleName: bundleName,
    quantity: quantity,
    overridePrice: overridePrice,
    discountReason: discountReason,
    weightGrams: weightGrams,
  );

  // 小計。量り売り商品は重量(g)と100gあたり単価から算出する
  int get subtotal {
    if (weightGrams != null) {
      return (price * weightGrams! / 100).round();
    }
    return price * quantity;
  }

  // 消費税額（税込価格から逆算）
  int get taxAmount {
    final taxRate = product.taxRate;
    final exTax = (subtotal * 100 / (100 + taxRate)).floor();
    return subtotal - exTax;
  }

  Map<String, dynamic> toJson() => {
    'product': product.toMap(),
    'bundle_code': bundleCode,
    'bundle_name': bundleName,
    'quantity': quantity,
    'override_price': overridePrice,
    'discount_reason': discountReason,
    'weight_grams': weightGrams,
  };

  factory ScannedItem.fromJson(Map<String, dynamic> json) {
    return ScannedItem(
      product: Product.fromMap(json['product'] as Map<String, dynamic>),
      bundleCode: json['bundle_code'] as String?,
      bundleName: json['bundle_name'] as String?,
      quantity: (json['quantity'] as num).toInt(),
      overridePrice: json['override_price'] as int?,
      discountReason: json['discount_reason'] as String?,
      weightGrams: (json['weight_grams'] as num?)?.toInt(),
    );
  }
}
