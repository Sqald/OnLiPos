class Product {
  final int id;
  final String code;
  final String name;
  final int price;

  Product({
    required this.id,
    required this.code,
    required this.name,
    required this.price,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as int,
      code: map['code'] as String,
      name: map['name'] as String,
      price: map['price'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'price': price,
    };
  }
}

