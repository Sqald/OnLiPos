/// サーバーから商品マスタ（商品・セット商品）を取得し、
/// ローカルSQLiteへ全件同期するサービス。
library;

import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:onlipos/api/pos_api_client.dart';
import 'package:onlipos/product/catalog_service.dart';
import 'package:onlipos/product/database_service.dart';
import 'package:onlipos/product/product.dart';

/// 商品マスタ同期サービス本体。1回の同期でローカルDBを一度リセットし、
/// ページングされたAPIレスポンスを繰り返し取得してDBへ反映する。
class ProductSyncService {
  final String baseUrl;
  final String authToken;

  ProductSyncService({required String baseUrl, required this.authToken})
    : baseUrl = PosApiClient.normalizeBaseUrl(baseUrl);

  /// 1ページ（最大1000件）の取得待ち上限。応答がないまま起動処理が止まるのを防ぐ
  static const _pageTimeout = Duration(seconds: 60);

  /// 商品マスタの同期を実行する
  /// [onProgress] コールバックで現在の処理件数を通知します
  Future<void> syncProducts({Function(int count)? onProgress}) async {
    final db = await DatabaseService.instance.database;
    // 1. 毎回フルフェッチする（サーバー側で削除された商品がローカルに残り続けるのを防ぐ）。
    //    取得がすべて終わるまで端末のマスタは書き換えず、途中で通信が切れても今までのマスタで会計を続けられる
    final List<Map<String, dynamic>> rows = [];
    Map<String, dynamic> lastPage = {};
    String lastUpdatedAt = '';
    int lastId = 0;

    bool hasMore = true;
    int totalProcessed = 0;
    List<dynamic> lastBundles = [];

    developer.log('Start full product sync');

    try {
      while (hasMore) {
        // 2. APIリクエストの構築
        final uri = Uri.parse('$baseUrl/api/v1/products/sync');

        final response = await http
            .post(
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
            )
            .timeout(_pageTimeout);

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
          lastPage = data;
          break;
        }

        // 3. 商品データを貯める（保存は全ページの取得後にまとめて行う）
        rows.addAll(
          products
              .map((p) => Product.fromMap(p as Map<String, dynamic>))
              .map((p) => {...p.toMap(), 'status': p.status}),
        );
        lastPage = data;

        // 4. 進捗の更新と出力
        totalProcessed += products.length;
        if (onProgress != null) {
          onProgress(totalProcessed);
        }
        developer.log('Synced $totalProcessed products so far...');

        // 5. 次のループのためのパラメータ更新
        hasMore = data['has_more'] ?? false;

        if (data['last_updated_at'] != null) {
          lastUpdatedAt = data['last_updated_at'];
        }
        if (data['last_id'] != null) {
          lastId = data['last_id'];
        }
      }

      // 6. 全ページ取得完了後、商品・セット商品・その他のマスタを一括で入れ替える
      await db.transaction((txn) async {
        await txn.delete('products');
        final productBatch = txn.batch();
        for (final row in rows) {
          productBatch.insert(
            'products',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await productBatch.commit(noResult: true);
        await CatalogService.saveMeta(txn, lastPage);

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

      CatalogService.instance.invalidate();
      await CatalogService.saveSettings(
        lastPage['settings'] as Map<String, dynamic>?,
      );
      developer.log('Product sync completed. Total: $totalProcessed');
    } catch (e) {
      developer.log('Error during product sync: $e');
      rethrow;
    }
  }
}
