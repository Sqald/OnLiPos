/// ローカルDBに未同期の商品をサーバーへ直接問い合わせるAPIクライアント。
/// スキャンしたJAN/商品コードがローカルキャッシュに見つからない場合の
/// フォールバック用に利用する。
library;

import 'dart:convert';

import 'package:onlipos/api/pos_api_client.dart';
import 'package:onlipos/product/product.dart';

class ProductLookupApi {
  /// サーバにコードで商品を問い合わせる。
  /// 見つからない場合は null を返す。通信エラー時は例外を投げる。
  static Future<Product?> lookupByCode(String code) async {
    final response = await PosApiClient.send(
      'GET',
      '/api/v1/products/lookup',
      query: {'code': code},
    );

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('サーバエラー: ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    if (data['success'] != true) return null;

    return Product.fromMap(data['product'] as Map<String, dynamic>);
  }
}
