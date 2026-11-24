/// 商品マスタのモデルクラス群。
/// Product はローカルDB（sqflite）の products テーブルと1対1で対応し、
/// ProductBundle / BundleItem はセット商品とその構成商品を表す。
library;

import 'dart:convert';

/// 税区分（サーバーの Product.tax_type と同じ番号）
class TaxType {
  static const inclusive = 0; // 内税
  static const exclusive = 1; // 外税
  static const taxFree = 2; // 非課税
}

/// 商品オプションの選択肢（トッピングなど）
class OptionItem {
  final int id;
  final String name;
  final int price;

  const OptionItem({required this.id, required this.name, required this.price});

  factory OptionItem.fromMap(Map<String, dynamic> map) => OptionItem(
    id: (map['id'] as num).toInt(),
    name: map['name'] as String,
    price: (map['price'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'price': price};
}

/// 商品オプションのグループ。選択数は [minSelect]〜[maxSelect]
class OptionGroup {
  final int id;
  final String name;
  final int minSelect;
  final int maxSelect;
  final List<OptionItem> items;

  const OptionGroup({
    required this.id,
    required this.name,
    required this.minSelect,
    required this.maxSelect,
    required this.items,
  });

  factory OptionGroup.fromMap(Map<String, dynamic> map) => OptionGroup(
    id: (map['id'] as num).toInt(),
    name: map['name'] as String,
    minSelect: (map['min_select'] as num?)?.toInt() ?? 0,
    maxSelect: (map['max_select'] as num?)?.toInt() ?? 1,
    items: ((map['items'] as List<dynamic>?) ?? [])
        .map((i) => OptionItem.fromMap(i as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'min_select': minSelect,
    'max_select': maxSelect,
    'items': items.map((i) => i.toMap()).toList(),
  };
}

class Product {
  final int id;
  final String code;
  final String name;
  final String? description;
  // 適用価格（店舗売価があればそれ、なければ定価と同じ）
  final int price;
  // 定価（product.price カラムの値）。店舗売価がなければ price と同じ
  final int listPrice;
  final int taxRate; // 消費税率(%) デフォルト10
  final int taxType; // 税区分（TaxType）
  // 店内飲食の税率・価格（null は通常と同じ）
  final int? eatInTaxRate;
  final int? eatInPrice;
  // 年齢確認が必要な年齢（null は不要）
  final int? minAge;
  final int? categoryId;
  final String? categoryName;
  // 量り売り（計量）商品。true の場合、price は100gあたりの単価として扱う
  final bool soldByWeight;
  // バリエーション（同じグループ名の商品を1つにまとめて選ぶ）
  final String? variantGroup;
  final String? variantName;
  // 画像の版（null は画像なし）。値が変わったら取得し直す
  final int? imageVersion;
  final List<OptionGroup> optionGroups;
  final String? status;

  Product({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    required this.price,
    int? listPrice,
    this.taxRate = 10,
    this.taxType = TaxType.inclusive,
    this.eatInTaxRate,
    this.eatInPrice,
    this.minAge,
    this.categoryId,
    this.categoryName,
    this.soldByWeight = false,
    this.variantGroup,
    this.variantName,
    this.imageVersion,
    this.optionGroups = const [],
    this.status,
  }) : listPrice = listPrice ?? price;

  bool get hasStorePrice => listPrice != price;

  int basePrice(bool eatIn) => (eatIn ? eatInPrice : null) ?? price;
  int taxRateFor(bool eatIn) => (eatIn ? eatInTaxRate : null) ?? taxRate;

  // sqfliteのクエリ結果・APIの応答（Map）からProductを復元する
  factory Product.fromMap(Map<String, dynamic> map) {
    final price = (map['price'] as num).toInt();
    final weight = map['sold_by_weight'];
    final rawOptions = map['option_groups'];
    final List<dynamic> options = switch (rawOptions) {
      String s when s.isNotEmpty => jsonDecode(s) as List<dynamic>,
      List<dynamic> l => l,
      _ => const [],
    };
    return Product(
      id: (map['id'] as num).toInt(),
      code: map['code'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      price: price,
      listPrice: (map['list_price'] as num?)?.toInt() ?? price,
      taxRate: (map['tax_rate'] as num?)?.toInt() ?? 10,
      taxType: (map['tax_type'] as num?)?.toInt() ?? TaxType.inclusive,
      eatInTaxRate: (map['eat_in_tax_rate'] as num?)?.toInt(),
      eatInPrice: (map['eat_in_price'] as num?)?.toInt(),
      minAge: (map['min_age'] as num?)?.toInt(),
      categoryId: (map['category_id'] as num?)?.toInt(),
      categoryName: map['category_name'] as String?,
      soldByWeight: weight == 1 || weight == true,
      variantGroup: map['variant_group'] as String?,
      variantName: map['variant_name'] as String?,
      imageVersion: (map['image_version'] as num?)?.toInt(),
      optionGroups: options
          .map((g) => OptionGroup.fromMap(g as Map<String, dynamic>))
          .toList(),
      status: map['status'] as String?,
    );
  }

  // sqfliteへ保存するためのMapに変換する（カートの共有にも使う）
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'description': description,
      'price': price,
      'list_price': listPrice,
      'tax_rate': taxRate,
      'tax_type': taxType,
      'eat_in_tax_rate': eatInTaxRate,
      'eat_in_price': eatInPrice,
      'min_age': minAge,
      'category_id': categoryId,
      'category_name': categoryName,
      'sold_by_weight': soldByWeight ? 1 : 0,
      'variant_group': variantGroup,
      'variant_name': variantName,
      'image_version': imageVersion,
      'option_groups': jsonEncode(optionGroups.map((g) => g.toMap()).toList()),
    };
  }

  Product copyWith({
    int? price,
    int? listPrice,
    int? taxRate,
    int? taxType,
    int? eatInTaxRate,
    int? eatInPrice,
  }) => Product(
    id: id,
    code: code,
    name: name,
    description: description,
    price: price ?? this.price,
    listPrice: listPrice ?? this.listPrice,
    taxRate: taxRate ?? this.taxRate,
    taxType: taxType ?? this.taxType,
    eatInTaxRate: eatInTaxRate ?? this.eatInTaxRate,
    eatInPrice: eatInPrice ?? this.eatInPrice,
    minAge: minAge,
    categoryId: categoryId,
    categoryName: categoryName,
    soldByWeight: soldByWeight,
    variantGroup: variantGroup,
    variantName: variantName,
    imageVersion: imageVersion,
    optionGroups: optionGroups,
    status: status,
  );
}

// セット商品の構成アイテム
class BundleItem {
  final int productId;
  final String? productCode;
  final int quantity;

  BundleItem({
    required this.productId,
    this.productCode,
    required this.quantity,
  });
}

// セット商品
class ProductBundle {
  final int id;
  final String code;
  final String name;
  final int price; // 0 なら構成商品の合計金額を使用
  final List<BundleItem> items;

  ProductBundle({
    required this.id,
    required this.code,
    required this.name,
    required this.price,
    required this.items,
  });
}
