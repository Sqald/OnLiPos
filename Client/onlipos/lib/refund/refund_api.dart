import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class RefundApi {
  static const _storage = FlutterSecureStorage();

  static Future<String?> _baseUrlAndToken() async {
    final baseUrl = await _storage.read(key: 'AccessUrl');
    final token = await _storage.read(key: 'LoginToken');
    if (baseUrl == null || token == null) return null;
    final normalized =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$normalized|$token';
  }

  static Map<String, dynamic> _parseResponse(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return {'success': false, 'message': 'サーバーエラー: ${response.statusCode}'};
    }
  }

  /// レシート番号で売上を取得（返品対象の会計）
  static Future<Map<String, dynamic>> getSaleByReceipt(String receiptNumber) async {
    final urlToken = await _baseUrlAndToken();
    if (urlToken == null) {
      return {'success': false, 'message': '認証情報がありません'};
    }
    final parts = urlToken.split('|');
    final baseUrl = parts[0];
    final token = parts[1];
    final uri = Uri.parse('$baseUrl/api/v1/refunds/sale_by_receipt')
        .replace(queryParameters: {'receipt_number': receiptNumber});

    try {
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      return _parseResponse(response);
    } catch (e) {
      return {'success': false, 'message': '通信エラー: $e'};
    }
  }

  /// 返品・返金を登録。details: [{ saledetail_id, quantity }, ...]
  static Future<Map<String, dynamic>> createRefund({
    required String receiptNumber,
    required List<int> employeeIds,
    required List<Map<String, dynamic>> details,
  }) async {
    final urlToken = await _baseUrlAndToken();
    if (urlToken == null) {
      return {'success': false, 'message': '認証情報がありません'};
    }
    final parts = urlToken.split('|');
    final baseUrl = parts[0];
    final token = parts[1];
    final uri = Uri.parse('$baseUrl/api/v1/refunds');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'receipt_number': receiptNumber,
          'employee_ids': employeeIds,
          'details': details,
        }),
      );
      return _parseResponse(response);
    } catch (e) {
      return {'success': false, 'message': '通信エラー: $e'};
    }
  }
}
