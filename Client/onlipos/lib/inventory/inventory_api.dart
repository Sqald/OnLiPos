import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// 在庫の入出荷を行うAPIクライアント。
class InventoryApi {
  static const _storage = FlutterSecureStorage();

  Future<Map<String, dynamic>> moveStocks({
    required int employeeId,
    required List<Map<String, dynamic>> movements,
  }) async {
    final baseUrl = await _storage.read(key: 'AccessUrl');
    final token = await _storage.read(key: 'LoginToken');

    if (baseUrl == null || baseUrl.isEmpty) {
      return {'success': false, 'message': '接続先URLが設定されていません'};
    }
    if (token == null || token.isEmpty) {
      return {'success': false, 'message': '端末認証トークンが見つかりません'};
    }

    final normalizedUrl =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final url = Uri.parse('$normalizedUrl/api/v1/store_stocks/move');

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'employee_id': employeeId,
          'movements': movements,
        }),
      );

      try {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        return {'success': false, 'message': 'サーバーエラー: ${response.statusCode}'};
      }
    } catch (e) {
      return {
        'success': false,
        'message': '通信エラーが発生しました: $e',
      };
    }
  }
}
