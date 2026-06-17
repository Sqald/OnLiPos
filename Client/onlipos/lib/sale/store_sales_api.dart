import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class StoreSalesApi {
  static const _storage = FlutterSecureStorage();

  static Future<Map<String, dynamic>> fetchSales({String? date}) async {
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
    final query = date != null ? '?date=$date' : '';
    final url = Uri.parse('$normalizedUrl/api/v1/sales$query');

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on SocketException {
      return {'success': false, 'message': 'ネットワークに接続できません'};
    } catch (e) {
      return {'success': false, 'message': '通信エラーが発生しました'};
    }
  }
}
