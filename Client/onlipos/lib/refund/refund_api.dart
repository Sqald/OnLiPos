/// 返品・返金処理用のAPIクライアント。レシート番号から対象の売上を検索し、
/// 返品内容をサーバーへ登録する。
library;

import 'package:onlipos/api/pos_api_client.dart';

class RefundApi {
  /// レシート番号で売上を取得（返品対象の会計）
  static Future<Map<String, dynamic>> getSaleByReceipt(String receiptNumber) {
    return PosApiClient.request(
      'GET',
      '/api/v1/refunds/sale_by_receipt',
      query: {'receipt_number': receiptNumber},
    );
  }

  /// 返品・返金を登録。details: [{ saledetail_id, quantity }, ...]
  static Future<Map<String, dynamic>> createRefund({
    required String receiptNumber,
    required List<int> employeeIds,
    required List<Map<String, dynamic>> details,
  }) {
    return PosApiClient.request(
      'POST',
      '/api/v1/refunds',
      body: {
        'receipt_number': receiptNumber,
        'employee_ids': employeeIds,
        'details': details,
      },
    );
  }
}
