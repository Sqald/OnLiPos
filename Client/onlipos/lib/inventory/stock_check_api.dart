/// 店舗在庫の一覧を取得するAPIクライアント。
/// 在庫確認画面（StockCheckView）から呼び出される。
library;

import 'package:onlipos/api/pos_api_client.dart';

class StockCheckApi {
  /// 現在ログイン中の店舗の在庫一覧をサーバーから取得する
  static Future<Map<String, dynamic>> fetchStocks() {
    return PosApiClient.request('GET', '/api/v1/store_stocks');
  }
}
