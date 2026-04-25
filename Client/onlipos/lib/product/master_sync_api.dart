import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:onlipos/product/database_service.dart';

class ProductSyncService {
  final String baseUrl;
  final String authToken;

  ProductSyncService({
    required this.baseUrl,
    required this.authToken,
  });

  /// 商品マスタの同期を実行する
  /// [onProgress] コールバックで現在の処理件数を通知します
  Future<void> syncProducts({Function(int count)? onProgress}) async {
    final db = await DatabaseService.instance.database;
    // 1. ローカルDBをリセットして毎回フルフェッチする
    //    （サーバー側で削除された商品がローカルに残り続けるのを防ぐ）
    await db.delete('products');
    String lastUpdatedAt = '';
    int lastId = 0;

    bool hasMore = true;
    int totalProcessed = 0;
    List<dynamic> lastBundles = [];

    developer.log('Start full product sync (DB reset)');

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
        lastBundles = data['bundles'] as List<dynamic>;

        // データが空で続きもない場合は終了
        if (products.isEmpty && data['has_more'] == false) {
          break;
        }

        // 3. 商品データをDBに保存（バンドルはループ完了後にまとめて処理）
        await db.transaction((txn) async {
          final batch = txn.batch();
          for (var product in products) {
            batch.insert(
              'products',
              {
                'id': product['id'],
                'code': product['code'],
                'name': product['name'],
                'description': product['description'],
                'price': product['price'],
                'tax_rate': product['tax_rate'] ?? 10,
                'status': product['status'],
                'updated_at': product['updated_at'],
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
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

        if (data['last_updated_at'] != null) {
          lastUpdatedAt = data['last_updated_at'];
        }
        if (data['last_id'] != null) {
          lastId = data['last_id'];
        }
      }

      // 6. 全商品ページ取得完了後、バンドルを一括で更新
      await db.transaction((txn) async {
        await txn.delete('product_bundle_items');
        await txn.delete('product_bundles');
        final bundleBatch = txn.batch();
        for (var bundle in lastBundles) {
          bundleBatch.insert('product_bundles', {
            'id': bundle['id'],
            'code': bundle['code'],
            'name': bundle['name'],
            'price': bundle['price'] ?? 0,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          for (var item in (bundle['items'] as List<dynamic>)) {
            bundleBatch.insert('product_bundle_items', {
              'product_bundle_id': bundle['id'],
              'product_id': item['product_id'],
              'product_code': item['product_code'],
              'quantity': item['quantity'] ?? 1,
            });
          }
        }
        await bundleBatch.commit(noResult: true);
      });

      developer.log('Product sync completed. Total: $totalProcessed');

    } catch (e) {
      developer.log('Error during product sync: $e');
      rethrow;
    }
  }
}