/// 商品マスタのモデルクラス群。
/// Product はローカルDB（sqflite）の products テーブルと1対1で対応し、
/// ProductBundle / BundleItem はセット商品とその構成商品を表す。
library;

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
  final int? categoryId;
  final String? categoryName;

  Product({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    required this.price,
    int? listPrice,
    this.taxRate = 10,
    this.categoryId,
    this.categoryName,
  }) : listPrice = listPrice ?? price;

  bool get hasStorePrice => listPrice != price;

  // sqfliteのクエリ結果（Map）からProductを復元する
  factory Product.fromMap(Map<String, dynamic> map) {
    final price = map['price'] as int;
    return Product(
      id: map['id'] as int,
      code: map['code'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      price: price,
      listPrice: (map['list_price'] as int?) ?? price,
      taxRate: (map['tax_rate'] as int?) ?? 10,
      categoryId: map['category_id'] as int?,
      categoryName: map['category_name'] as String?,
    );
  }

  // sqfliteへ保存するためのMapに変換する
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'description': description,
      'price': price,
      'list_price': listPrice,
      'tax_rate': taxRate,
      'category_id': categoryId,
      'category_name': categoryName,
    };
  }
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
