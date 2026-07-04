import 'package:flutter_test/flutter_test.dart';
import 'package:onlipos/pop/pop_pdf_builder.dart';
import 'package:onlipos/product/product.dart';

Product _product({int id = 1, String code = '4901234567894'}) => Product(
  id: id,
  code: code,
  name: 'テスト商品$id',
  description: '説明テキスト',
  price: 1000,
  taxRate: 10,
);

void main() {
  group('PopPdfBuilder.pageCount', () {
    test('空リスト → 0ページ', () {
      expect(PopPdfBuilder.pageCount([], 4), 0);
    });

    test('1面: 1商品1枚 → 1ページ', () {
      final items = [PopItem(product: _product())];
      expect(PopPdfBuilder.pageCount(items, 1), 1);
    });

    test('1面: 3商品1枚ずつ → 3ページ', () {
      final items = [
        PopItem(product: _product(id: 1)),
        PopItem(product: _product(id: 2)),
        PopItem(product: _product(id: 3)),
      ];
      expect(PopPdfBuilder.pageCount(items, 1), 3);
    });

    test('2面: 2商品1枚ずつ → 1ページ', () {
      final items = [
        PopItem(product: _product(id: 1)),
        PopItem(product: _product(id: 2)),
      ];
      expect(PopPdfBuilder.pageCount(items, 2), 1);
    });

    test('2面: 合計9枚 → 5ページ (ceil(9/2))', () {
      final items = [
        PopItem(product: _product(id: 1), count: 5),
        PopItem(product: _product(id: 2), count: 4),
      ];
      expect(PopPdfBuilder.pageCount(items, 2), 5);
    });

    test('4面: 合計3枚 → 1ページ', () {
      final items = [PopItem(product: _product(), count: 3)];
      expect(PopPdfBuilder.pageCount(items, 4), 1);
    });

    test('4面: 合計4枚 → 1ページ', () {
      final items = [PopItem(product: _product(), count: 4)];
      expect(PopPdfBuilder.pageCount(items, 4), 1);
    });

    test('4面: 合計5枚 → 2ページ', () {
      final items = [PopItem(product: _product(), count: 5)];
      expect(PopPdfBuilder.pageCount(items, 4), 2);
    });

    test('8面: 合計8枚 → 1ページ', () {
      final items = [
        PopItem(product: _product(id: 1), count: 3),
        PopItem(product: _product(id: 2), count: 5),
      ];
      expect(PopPdfBuilder.pageCount(items, 8), 1);
    });

    test('8面: 合計9枚 → 2ページ', () {
      final items = [PopItem(product: _product(), count: 9)];
      expect(PopPdfBuilder.pageCount(items, 8), 2);
    });

    test('16面: 16枚 → 1ページ', () {
      final items = [PopItem(product: _product(), count: 16)];
      expect(PopPdfBuilder.pageCount(items, 16), 1);
    });

    test('16面: 17枚 → 2ページ', () {
      final items = [PopItem(product: _product(), count: 17)];
      expect(PopPdfBuilder.pageCount(items, 16), 2);
    });

    test('count=0 の商品は合計に含まれない', () {
      final items = [
        PopItem(product: _product(id: 1), count: 0),
        PopItem(product: _product(id: 2), count: 4),
      ];
      expect(PopPdfBuilder.pageCount(items, 4), 1);
    });
  });
}
