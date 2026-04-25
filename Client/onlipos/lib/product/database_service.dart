import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// アプリ全体で共有するSQLiteデータベース接続のシングルトン。
/// ProductRepository / OfflineSaleRepository など複数クラスが
/// 同一DBファイルを別々にオープンすることによる "database is locked" を防ぐ。
class DatabaseService {
  static const _dbName = 'pos_app.db';
  static const _dbVersion = 4;

  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    String path;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      path = join(dir.path, _dbName);
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, _dbName);
    }

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY,
        code TEXT,
        name TEXT,
        description TEXT,
        price INTEGER,
        tax_rate INTEGER DEFAULT 10,
        status TEXT,
        updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE product_bundles (
        id INTEGER PRIMARY KEY,
        code TEXT UNIQUE,
        name TEXT,
        price INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE product_bundle_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_bundle_id INTEGER,
        product_id INTEGER,
        product_code TEXT,
        quantity INTEGER DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE offline_sales_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_number TEXT,
        payload TEXT,
        created_at TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE products ADD COLUMN tax_category INTEGER DEFAULT 0');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS product_bundles (
          id INTEGER PRIMARY KEY,
          code TEXT UNIQUE,
          name TEXT,
          price INTEGER DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS product_bundle_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_bundle_id INTEGER,
          product_id INTEGER,
          product_code TEXT,
          quantity INTEGER DEFAULT 1
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS offline_sales_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          receipt_number TEXT,
          payload TEXT,
          created_at TEXT
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE products ADD COLUMN tax_rate INTEGER DEFAULT 10');
      // v2移行で追加された tax_category から値を移行（存在しない場合は無視）
      try {
        await db.execute(
          'UPDATE products SET tax_rate = CASE tax_category WHEN 1 THEN 8 ELSE 10 END',
        );
        await db.execute('ALTER TABLE products DROP COLUMN tax_category');
      } catch (_) {
        // 古いSQLiteバージョン（3.35未満）では DROP COLUMN 非対応のため無視
      }
    }
  }
}
