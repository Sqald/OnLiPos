import 'package:flutter_test/flutter_test.dart';
import 'package:onlipos/product/product.dart';
import 'package:onlipos/sale/sale_item.dart';

void main() {
  Product makeProduct({int price = 1000, int? listPrice, int taxRate = 10}) {
    return Product(
      id: 1,
      code: 'P001',
      name: 'テスト商品',
      price: price,
      listPrice: listPrice,
      taxRate: taxRate,
    );
  }

  group('Product.hasStorePrice', () {
    test('店舗売価がない場合は false', () {
      final p = makeProduct(price: 1000);
      expect(p.hasStorePrice, isFalse);
      expect(p.listPrice, equals(p.price));
    });

    test('店舗売価がある場合は true', () {
      final p = makeProduct(price: 900, listPrice: 1000);
      expect(p.hasStorePrice, isTrue);
      expect(p.listPrice, equals(1000));
      expect(p.price, equals(900));
    });
  });

  group('ScannedItem 価格・小計・税額', () {
    test('値引きなし: price = product.price', () {
      final item = ScannedItem(product: makeProduct(price: 1000), quantity: 2);
      expect(item.price, equals(1000));
      expect(item.subtotal, equals(2000));
      // 税10%逆算: 2000 * 100 / 110 = 1818、税額 = 182
      expect(item.taxAmount, equals(182));
    });

    test('overridePrice が設定された場合はその価格を使用', () {
      final item = ScannedItem(
        product: makeProduct(price: 1000),
        quantity: 1,
        overridePrice: 800,
        discountReason: '賞味期限値引き',
      );
      expect(item.price, equals(800));
      expect(item.subtotal, equals(800));
    });

    test('税率8%の逆算が正しい', () {
      final item = ScannedItem(
        product: makeProduct(price: 108, taxRate: 8),
        quantity: 1,
      );
      expect(item.subtotal, equals(108));
      // 108 * 100 / 108 = 100、税額 = 8
      expect(item.taxAmount, equals(8));
    });

    test('overridePrice = product.price のとき実質的に値引きなし', () {
      final product = makeProduct(price: 1000);
      final item = ScannedItem(
        product: product,
        quantity: 1,
        overridePrice: 1000,
      );
      expect(item.price, equals(1000));
      expect(item.subtotal, equals(1000));
    });
  });

  group('ScannedItem.copy()', () {
    test('discountReason も複製される', () {
      final item = ScannedItem(
        product: makeProduct(),
        quantity: 3,
        overridePrice: 800,
        discountReason: '値引き理由',
      );
      final copied = item.copy();
      expect(copied.discountReason, equals('値引き理由'));
      expect(copied.overridePrice, equals(800));
      expect(copied.quantity, equals(3));
    });
  });

  group('ScannedItem JSON round-trip', () {
    test('toJson/fromJson が discountReason を正しく保持する', () {
      final product = makeProduct(price: 900, listPrice: 1000);
      final item = ScannedItem(
        product: product,
        quantity: 2,
        overridePrice: 700,
        discountReason: '期限間近',
      );
      final json = item.toJson();
      final restored = ScannedItem.fromJson(json);
      expect(restored.overridePrice, equals(700));
      expect(restored.discountReason, equals('期限間近'));
      expect(restored.product.listPrice, equals(1000));
      expect(restored.product.price, equals(900));
    });
  });

  group('Product.fromMap', () {
    test('list_price がある場合は listPrice に設定される', () {
      final map = {
        'id': 1,
        'code': 'P001',
        'name': '商品',
        'price': 900,
        'list_price': 1000,
        'tax_rate': 10,
      };
      final p = Product.fromMap(map);
      expect(p.price, equals(900));
      expect(p.listPrice, equals(1000));
      expect(p.hasStorePrice, isTrue);
    });

    test('list_price がない場合は price と同じ', () {
      final map = {
        'id': 1,
        'code': 'P001',
        'name': '商品',
        'price': 1000,
        'tax_rate': 10,
      };
      final p = Product.fromMap(map);
      expect(p.listPrice, equals(1000));
      expect(p.hasStorePrice, isFalse);
    });
  });
}
