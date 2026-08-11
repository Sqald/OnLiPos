/// ローカルSQLiteの商品/セット商品テーブルへアクセスするリポジトリ。
/// 端末側での商品検索・カテゴリ一覧・セット商品展開など、
/// 販売画面や在庫画面から共通で利用される読み取り処理をまとめる。
library;

import 'package:sqflite/sqflite.dart';
import 'package:onlipos/product/database_service.dart';
import 'package:onlipos/product/product.dart';

class ProductRepository {
  Future<Database> get _db => DatabaseService.instance.database;

  // 全商品を取得する
  Future<List<Product>> getAllProducts() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query('products');
    return maps.map((map) => Product.fromMap(map)).toList();
  }

  // JAN/商品コードに完全一致する商品を1件取得する
  Future<Product?> findProductByCode(String code) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      where: 'code = ?',
      whereArgs: [code],
    );

    if (maps.isNotEmpty) {
      return Product.fromMap(maps[0]);
    }
    return null;
  }

  // 商品名の部分一致検索（最大50件）
  Future<List<Product>> searchByName(String query) async {
    if (query.isEmpty) return [];
    final db = await _db;
    final maps = await db.query(
      'products',
      where: 'name LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'name',
      limit: 50,
    );
    return maps.map((m) => Product.fromMap(m)).toList();
  }

  /// カテゴリIDごとの商品一覧（null = カテゴリなし）
  Future<List<Product>> getProductsByCategory(int? categoryId) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = categoryId == null
        ? await db.query('products', where: 'category_id IS NULL')
        : await db.query(
            'products',
            where: 'category_id = ?',
            whereArgs: [categoryId],
          );
    return maps.map((map) => Product.fromMap(map)).toList();
  }

  /// 登録されているカテゴリの一覧（重複なし）
  Future<List<({int id, String name})>> getCategories() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT DISTINCT category_id, category_name FROM products '
      'WHERE category_id IS NOT NULL ORDER BY category_name',
    );
    return rows
        .where((r) => r['category_id'] != null && r['category_name'] != null)
        .map(
          (r) =>
              (id: r['category_id'] as int, name: r['category_name'] as String),
        )
        .toList();
  }

  // コードに一致するセット商品を構成アイテムとあわせて1件取得する
  Future<ProductBundle?> findBundleByCode(String code) async {
    final db = await _db;
    final List<Map<String, dynamic>> rows = await db.query(
      'product_bundles',
      where: 'code = ?',
      whereArgs: [code],
    );
    if (rows.isEmpty) return null;

    final bundleRow = rows.first;
    final int bundleId = bundleRow['id'] as int;

    final itemRows = await db.query(
      'product_bundle_items',
      where: 'product_bundle_id = ?',
      whereArgs: [bundleId],
    );

    final items = itemRows
        .map(
          (r) => BundleItem(
            productId: r['product_id'] as int,
            productCode: r['product_code'] as String?,
            quantity: r['quantity'] as int,
          ),
        )
        .toList();

    return ProductBundle(
      id: bundleId,
      code: bundleRow['code'] as String,
      name: bundleRow['name'] as String,
      price: (bundleRow['price'] as int?) ?? 0,
      items: items,
    );
  }

  /// 全セット商品を返す（構成アイテム含む）
  Future<List<ProductBundle>> getAllBundles() async {
    final db = await _db;
    final bundleRows = await db.query('product_bundles');
    if (bundleRows.isEmpty) return [];

    final List<ProductBundle> result = [];
    for (final bundleRow in bundleRows) {
      final int bundleId = bundleRow['id'] as int;
      final itemRows = await db.query(
        'product_bundle_items',
        where: 'product_bundle_id = ?',
        whereArgs: [bundleId],
      );
      final items = itemRows
          .map(
            (r) => BundleItem(
              productId: r['product_id'] as int,
              productCode: r['product_code'] as String?,
              quantity: r['quantity'] as int,
            ),
          )
          .toList();
      result.add(
        ProductBundle(
          id: bundleId,
          code: bundleRow['code'] as String,
          name: bundleRow['name'] as String,
          price: (bundleRow['price'] as int?) ?? 0,
          items: items,
        ),
      );
    }
    return result;
  }

  // セットを構成商品リストに展開して返す
  Future<List<Product>> expandBundle(ProductBundle bundle) async {
    final db = await _db;
    final List<Product> result = [];
    for (final item in bundle.items) {
      final rows = await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [item.productId],
      );
      if (rows.isNotEmpty) {
        result.add(Product.fromMap(rows.first));
      }
    }
    return result;
  }
}
