// 会計中のカートに積まれた1商品分のデータモデル（ScannedItem）を定義する。
// セット商品・手動値引き・自動値引き・量り売り・オプション・店内飲食に対応する。
import 'package:onlipos/product/product.dart';

/// セット商品の構成商品（税額の計算に使う）。weight は1セットあたりの定価合計
class BundleComponent {
  final int weight;
  final int taxRate;
  final int? minAge;

  const BundleComponent({
    required this.weight,
    required this.taxRate,
    this.minAge,
  });

  Map<String, dynamic> toJson() => {
    'weight': weight,
    'tax_rate': taxRate,
    'min_age': minAge,
  };

  factory BundleComponent.fromJson(Map<String, dynamic> json) =>
      BundleComponent(
        weight: (json['weight'] as num).toInt(),
        taxRate: (json['tax_rate'] as num).toInt(),
        minAge: (json['min_age'] as num?)?.toInt(),
      );
}

/// スキャン／選択した商品1件分（数量・値引き・重量などを含む）。
class ScannedItem {
  final Product product;
  // セット商品のコード・名称。components がある場合、product はセットそのものを表す
  final String? bundleCode;
  final String? bundleName;
  final List<BundleComponent> components;
  int quantity;
  // null の場合は通常価格（または自動値引き）を使用。手動の価格変更で上書きする
  int? overridePrice;
  // 値引き理由（手動値引き時のみ）
  String? discountReason;
  // 量り売り（計量）商品の重量(g)。product.soldByWeight の商品のみ設定される。
  // 設定時は price を100gあたりの単価として重量から金額を算出する
  int? weightGrams;
  // 店内飲食
  bool eatIn;
  // 選択したオプション（1点あたりの追加料金を含む）
  final List<OptionItem> options;
  // 自動値引き（タイムセール）。CartPricing が会計時刻から設定する
  int? promotionPrice;
  String? promotionName;

  ScannedItem({
    required this.product,
    this.bundleCode,
    this.bundleName,
    this.components = const [],
    this.quantity = 1,
    this.overridePrice,
    this.discountReason,
    this.weightGrams,
    this.eatIn = false,
    this.options = const [],
  });

  /// セット商品1件を表す（構成商品ごとではなくセットとして送信する）
  bool get isBundle => bundleCode != null && components.isNotEmpty;

  int get optionsPrice => options.fold(0, (s, o) => s + o.price);
  int get regularPrice => product.basePrice(eatIn) + optionsPrice;

  int get price =>
      (overridePrice ?? promotionPrice ?? product.basePrice(eatIn)) +
      optionsPrice;

  int get taxRate => product.taxRateFor(eatIn);

  // 同じ行にまとめて数量を加算できるか
  bool canMerge(Product other, {bool eatIn = false}) =>
      product.id == other.id &&
      bundleCode == null &&
      overridePrice == null &&
      weightGrams == null &&
      options.isEmpty &&
      other.optionGroups.isEmpty &&
      this.eatIn == eatIn;

  // カート内で独立に扱えるようディープコピーを作成する
  ScannedItem copy() => ScannedItem(
    product: product,
    bundleCode: bundleCode,
    bundleName: bundleName,
    components: components,
    quantity: quantity,
    overridePrice: overridePrice,
    discountReason: discountReason,
    weightGrams: weightGrams,
    eatIn: eatIn,
    options: options,
  );

  // 小計。量り売り商品は重量(g)と100gあたり単価から算出する
  int get subtotal {
    if (weightGrams != null) {
      return (price * weightGrams! / 100).round();
    }
    return price * quantity;
  }

  // 消費税額（表示用の参考値。会計の確定値は CartPricing が税率ごとに計算する）
  int get taxAmount {
    switch (product.taxType) {
      case TaxType.exclusive:
        return subtotal * taxRate ~/ 100;
      case TaxType.taxFree:
        return 0;
      default:
        return subtotal - subtotal * 100 ~/ (100 + taxRate);
    }
  }

  Map<String, dynamic> toJson() => {
    'product': product.toMap(),
    'bundle_code': bundleCode,
    'bundle_name': bundleName,
    'components': components.map((c) => c.toJson()).toList(),
    'quantity': quantity,
    'override_price': overridePrice,
    'discount_reason': discountReason,
    'weight_grams': weightGrams,
    'eat_in': eatIn,
    'options': options.map((o) => o.toMap()).toList(),
  };

  factory ScannedItem.fromJson(Map<String, dynamic> json) {
    return ScannedItem(
      product: Product.fromMap(json['product'] as Map<String, dynamic>),
      bundleCode: json['bundle_code'] as String?,
      bundleName: json['bundle_name'] as String?,
      components: ((json['components'] as List<dynamic>?) ?? [])
          .map((c) => BundleComponent.fromJson(c as Map<String, dynamic>))
          .toList(),
      quantity: (json['quantity'] as num).toInt(),
      overridePrice: (json['override_price'] as num?)?.toInt(),
      discountReason: json['discount_reason'] as String?,
      weightGrams: (json['weight_grams'] as num?)?.toInt(),
      eatIn: json['eat_in'] == true,
      options: ((json['options'] as List<dynamic>?) ?? [])
          .map((o) => OptionItem.fromMap(o as Map<String, dynamic>))
          .toList(),
    );
  }
}
