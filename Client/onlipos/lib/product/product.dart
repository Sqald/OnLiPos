class Product {
  final int id;
  final String code;
  final String name;
  final int price;
  final int taxRate; // 消費税率(%) デフォルト10

  Product({
    required this.id,
    required this.code,
    required this.name,
    required this.price,
    this.taxRate = 10,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as int,
      code: map['code'] as String,
      name: map['name'] as String,
      price: map['price'] as int,
      taxRate: (map['tax_rate'] as int?) ?? 10,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'price': price,
      'tax_rate': taxRate,
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
