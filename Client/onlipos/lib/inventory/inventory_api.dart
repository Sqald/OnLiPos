import 'package:onlipos/api/pos_api_client.dart';

/// 在庫の入出荷を行うAPIクライアント。
class InventoryApi {
  /// 入出荷明細（movements）をまとめてサーバーへ送信し、店舗在庫を更新する
  Future<Map<String, dynamic>> moveStocks({
    required int employeeId,
    required List<Map<String, dynamic>> movements,
  }) {
    return PosApiClient.request(
      'POST',
      '/api/v1/store_stocks/move',
      body: {'employee_id': employeeId, 'movements': movements},
    );
  }
}
