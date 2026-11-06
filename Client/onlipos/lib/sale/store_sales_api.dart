// 店舗売上サマリー（/api/v1/sales/summary）を取得するAPIクライアント。
// 店舗売上閲覧画面（StoreSalesView）から期間指定で呼び出される。
import 'package:onlipos/api/pos_api_client.dart';

class StoreSalesApi {
  /// 指定期間（[from]〜[to]、YYYY-MM-DD）の売上サマリーを取得する。
  static Future<Map<String, dynamic>> fetchSummary({
    required int employeeId,
    required String from,
    required String to,
  }) {
    return PosApiClient.request(
      'GET',
      '/api/v1/sales/summary',
      query: {'employee_id': employeeId.toString(), 'from': from, 'to': to},
    );
  }
}
