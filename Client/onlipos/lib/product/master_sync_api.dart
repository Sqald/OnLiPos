import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class ProductSyncService {
  Database? _db;
  final String baseUrl;
  final String authToken;

  ProductSyncService({
    Database? db,
    required this.baseUrl,
    required this.authToken,
  }) : _db = db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    String path;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      path = join(dir.path, 'pos_app.db');
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, 'pos_app.db');
    }

    developer.log('Database path: $path');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products (
            id INTEGER PRIMARY KEY,
            code TEXT,
            name TEXT,
            description TEXT,
            price INTEGER,
            status TEXT,
            updated_at TEXT
          )
        ''');
      },
    );
  }

  /// 商品マスタの同期を実行する
  /// [onProgress] コールバックで現在の処理件数を通知します
  Future<void> syncProducts({Function(int count)? onProgress}) async {
    final db = await _database;
    const storage = FlutterSecureStorage();

    // 1. 前回の同期位置を取得 (未設定の場合は初期値)
    // サーバー側は Time.at(0) をデフォルトとしているので、空文字または初期日時を送る
    String lastUpdatedAt = await storage.read(key: 'sync_products_last_updated_at') ?? '';
    int lastId = int.tryParse(await storage.read(key: 'sync_products_last_id') ?? '0') ?? 0;

    bool hasMore = true;
    int totalProcessed = 0;

    developer.log('Start syncing products from: $lastUpdatedAt, id: $lastId');

    try {
      while (hasMore) {
        // 2. APIリクエストの構築
        final uri = Uri.parse('$baseUrl/api/v1/products/sync');

        final response = await http.post(
          uri,
          headers: {
            'Authorization': 'Bearer $authToken',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: json.encode({
            if (lastUpdatedAt.isNotEmpty) 'last_updated_at': lastUpdatedAt,
            'last_id': lastId,
          }),
        );

        if (response.statusCode != 200) {
          throw Exception('API Error: ${response.statusCode} ${response.body}');
        }

        final Map<String, dynamic> data = json.decode(response.body);

        if (data['success'] != true) {
          throw Exception('Sync failed: ${data['message']}');
        }

        final List<dynamic> products = data['products'];
        
        // データが空で続きもない場合は終了
        if (products.isEmpty && data['has_more'] == false) {
          break;
        }

        // 3. データベースへの保存 (トランザクションを使用)
        await db.transaction((txn) async {
          final batch = txn.batch();
          for (var product in products) {
            // SQLiteへのInsert/Update (ConflictAlgorithm.replaceを使用)
            // 事前にDB側で products テーブルを作成しておく必要があります
            batch.insert(
              'products',
              {
                'id': product['id'],
                'code': product['code'],
                'name': product['name'],
                'description': product['description'],
                'price': product['price'], // 店舗価格または基本価格が入っている
                'status': product['status'], // 文字列 ("active" or "discontinued")
                'updated_at': product['updated_at'],
              },
              conflictAlgorithm: ConflictAlgorithm.replace, // IDが同じなら上書き
            );
          }
          await batch.commit(noResult: true);
        });

        // 4. 進捗の更新と出力
        totalProcessed += products.length;
        if (onProgress != null) {
          onProgress(totalProcessed);
        }
        print('Synced $totalProcessed products so far...'); // コンソールに進捗出力

        // 5. 次のループのためのパラメータ更新
        hasMore = data['has_more'] ?? false;
        
        // サーバーから返却された「次回の同期開始位置」を取得してメモリ上で更新
        if (data['last_updated_at'] != null) {
          lastUpdatedAt = data['last_updated_at'];
        }
        if (data['last_id'] != null) {
          lastId = data['last_id'];
        }
      }

      // 6. 全同期完了後、次回の開始位置を永続化
      await storage.write(key: 'sync_products_last_updated_at', value: lastUpdatedAt);
      await storage.write(key: 'sync_products_last_id', value: lastId.toString());
      
      developer.log('Product sync completed. Total: $totalProcessed');

    } catch (e) {
      developer.log('Error during product sync: $e');
      rethrow;
    }
  }
}