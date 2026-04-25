import 'package:onlipos/product/product.dart';

class ScannedItem {
  final Product product;
  // セット商品から展開された場合のセットコード
  final String? bundleCode;
  final String? bundleName;
  int quantity;
  // null の場合は product.price を使用。値引き・賞味期限値変更などで上書きする
  int? overridePrice;

  ScannedItem({
    required this.product,
    this.bundleCode,
    this.bundleName,
    this.quantity = 1,
    this.overridePrice,
  });

  int get price => overridePrice ?? product.price;

  ScannedItem copy() => ScannedItem(
        product: product,
        bundleCode: bundleCode,
        bundleName: bundleName,
        quantity: quantity,
        overridePrice: overridePrice,
      );

  int get subtotal => price * quantity;

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
      };

  factory ScannedItem.fromJson(Map<String, dynamic> json) {
    return ScannedItem(
      product: Product.fromMap(json['product'] as Map<String, dynamic>),
      bundleCode: json['bundle_code'] as String?,
      bundleName: json['bundle_name'] as String?,
      quantity: (json['quantity'] as num).toInt(),
      overridePrice: json['override_price'] as int?,
    );
  }
}
