/// 店舗独自価格(店舗売価)の取得・更新を行うAPIクライアント。
library;

import 'package:onlipos/api/pos_api_client.dart';

class PriceApi {
  /// 店舗の商品価格一覧をページング取得する(検索クエリ・続き読み込み対応)
  static Future<Map<String, dynamic>> fetchStorePrices({
    required int employeeId,
    String query = '',
    int lastId = 0,
  }) {
    return PosApiClient.request(
      'GET',
      '/api/v1/store_prices',
      query: {
        'employee_id': employeeId.toString(),
        'last_id': lastId.toString(),
        if (query.isNotEmpty) 'q': query,
      },
    );
  }

  /// 指定商品の店舗売価を更新する(定価に戻す/固定金額を設定する)
  static Future<Map<String, dynamic>> updateStorePrice({
    required int employeeId,
    required int productId,
    required String mode,
    int? amount,
  }) {
    return PosApiClient.request(
      'PATCH',
      '/api/v1/store_prices',
      body: {
        'employee_id': employeeId,
        'product_id': productId,
        'mode': mode,
        'amount': ?amount,
      },
    );
  }
}
