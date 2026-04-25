import 'package:sqflite/sqflite.dart';
import 'package:onlipos/product/database_service.dart';
import 'package:onlipos/product/product.dart';

class ProductRepository {
  Future<Database> get _db => DatabaseService.instance.database;

  Future<List<Product>> getAllProducts() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query('products');
    return maps.map((map) => Product.fromMap(map)).toList();
  }

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

    final items = itemRows.map((r) => BundleItem(
      productId: r['product_id'] as int,
      productCode: r['product_code'] as String?,
      quantity: r['quantity'] as int,
    )).toList();

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
      final items = itemRows.map((r) => BundleItem(
        productId: r['product_id'] as int,
        productCode: r['product_code'] as String?,
        quantity: r['quantity'] as int,
      )).toList();
      result.add(ProductBundle(
        id: bundleId,
        code: bundleRow['code'] as String,
        name: bundleRow['name'] as String,
        price: (bundleRow['price'] as int?) ?? 0,
        items: items,
      ));
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
