import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:onlipos/product/product.dart';

class ProductRepository {
  static const String _dbName = 'pos_app.db';
  static const String _productTable = 'products';
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    String path;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final dir = await getApplicationSupportDirectory();
      path = join(dir.path, _dbName);
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, _dbName);
    }
    
    // テーブル作成は同期処理(ProductSyncService)で行われるため、
    // ここでは既存のDBを開くだけにする
    return await openDatabase(path, version: 1);
  }

  /// Finds a product by its barcode.
  ///
  /// Returns a [Product] if found, otherwise returns null.
  Future<Product?> findProductByCode(String code) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _productTable,
      where: 'code = ?',
      whereArgs: [code],
    );

    if (maps.isNotEmpty) {
      return Product(
        id: maps[0]['id'],
        code: maps[0]['code'],
        name: maps[0]['name'],
        price: maps[0]['price'],
      );
    } else {
      return null;
    }
  }
}
