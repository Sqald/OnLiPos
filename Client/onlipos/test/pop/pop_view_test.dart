import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlipos/pop/pop_view.dart';
import 'package:onlipos/product/product.dart';
import 'package:onlipos/product/product_repository.dart';

// DB を使わないフェイクリポジトリ
class _FakeRepo extends ProductRepository {
  final List<Product> _products;

  _FakeRepo(this._products);

  @override
  Future<Product?> findProductByCode(String code) async => _products
      .cast<Product?>()
      .firstWhere((p) => p!.code == code, orElse: () => null);

  @override
  Future<List<Product>> searchByName(String query) async =>
      _products.where((p) => p.name.contains(query)).toList();
}

Product _product({int id = 1, String code = '4901234567894'}) => Product(
  id: id,
  code: code,
  name: 'テスト商品$id',
  description: '説明テキスト',
  price: 1000,
  taxRate: 10,
);

Widget _app({ProductRepository? repo}) =>
    MaterialApp(home: PopView(repo: repo ?? _FakeRepo([])));

void main() {
  group('PopView', () {
    testWidgets('初期表示: タイトル・空メッセージ・面付けボタンが見える', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pump();

      expect(find.text('POP印刷'), findsOneWidget);
      expect(find.text('商品を追加してください'), findsOneWidget);
      expect(find.text('1面'), findsOneWidget);
      expect(find.text('4面'), findsOneWidget);
      expect(find.text('16面'), findsOneWidget);
    });

    testWidgets('商品名検索で結果が表示される', (tester) async {
      final repo = _FakeRepo([_product()]);
      await tester.pumpWidget(_app(repo: repo));
      await tester.pump();

      // 商品名フィールド（2番目のTextField）に入力
      final nameField = find.byType(TextField).at(1);
      await tester.enterText(nameField, 'テスト');
      await tester.pump();

      expect(find.text('テスト商品1'), findsOneWidget);
    });

    testWidgets('検索結果をタップすると印刷リストに追加される', (tester) async {
      final repo = _FakeRepo([_product()]);
      await tester.pumpWidget(_app(repo: repo));
      await tester.pump();

      // 商品名検索
      final nameField = find.byType(TextField).at(1);
      await tester.enterText(nameField, 'テスト');
      await tester.pump();

      // 検索結果の ListTile をタップ
      await tester.tap(find.text('テスト商品1'));
      await tester.pump();
      await tester.pump(); // onChanged('') が非同期なので追加pump

      // 空メッセージが消え、商品がリストに現れる
      expect(find.text('商品を追加してください'), findsNothing);
      // 商品名がリストタイルに表示される
      expect(find.text('テスト商品1'), findsAtLeastNWidgets(1));
    });

    testWidgets('+ ボタンで枚数が増える', (tester) async {
      final repo = _FakeRepo([_product()]);
      await tester.pumpWidget(_app(repo: repo));
      await tester.pump();

      // 商品を追加
      await tester.enterText(find.byType(TextField).at(1), 'テスト');
      await tester.pump();
      await tester.tap(find.text('テスト商品1'));
      await tester.pump();
      await tester.pump();

      // 初期枚数 1
      expect(find.text('1'), findsOneWidget);

      // + ボタン
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('- ボタンで枚数が減る（最小1）', (tester) async {
      final repo = _FakeRepo([_product()]);
      await tester.pumpWidget(_app(repo: repo));
      await tester.pump();

      // 商品を追加して枚数を2にする
      await tester.enterText(find.byType(TextField).at(1), 'テスト');
      await tester.pump();
      await tester.tap(find.text('テスト商品1'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();
      expect(find.text('2'), findsOneWidget);

      // - ボタン → 1 になる
      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);

      // さらに押しても 1 のまま（clamp）
      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('削除ボタンで商品がリストから消える', (tester) async {
      final repo = _FakeRepo([_product()]);
      await tester.pumpWidget(_app(repo: repo));
      await tester.pump();

      // 商品を追加
      await tester.enterText(find.byType(TextField).at(1), 'テスト');
      await tester.pump();
      await tester.tap(find.text('テスト商品1'));
      await tester.pump();
      await tester.pump();
      expect(find.text('商品を追加してください'), findsNothing);

      // 削除
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      expect(find.text('商品を追加してください'), findsOneWidget);
    });

    testWidgets('同じ商品を再度追加すると枚数が増える', (tester) async {
      final repo = _FakeRepo([_product()]);
      await tester.pumpWidget(_app(repo: repo));
      await tester.pump();

      // 1回目追加
      await tester.enterText(find.byType(TextField).at(1), 'テスト');
      await tester.pump();
      await tester.tap(find.text('テスト商品1').first);
      await tester.pump();
      await tester.pump();

      // 2回目追加（検索結果と印刷リストに同名テキストが出るので .first で検索結果側を選ぶ）
      await tester.enterText(find.byType(TextField).at(1), 'テスト');
      await tester.pump();
      await tester.tap(find.text('テスト商品1').first);
      await tester.pump();
      await tester.pump();

      // 枚数が2になっている
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('面付け選択ボタンが全種類表示される', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pump();

      for (final label in ['1面', '2面', '4面', '8面', '16面']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('JANコード検索フィールドと検索ボタンが表示される', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pump();

      expect(find.byIcon(Icons.qr_code), findsOneWidget);
      expect(find.text('検索'), findsOneWidget);
    });
  });
}
