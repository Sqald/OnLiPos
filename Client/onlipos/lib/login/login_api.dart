import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LoginApi {
  static Future<Map<String, dynamic>> userLogin({
    required String code,
    required String pin,
    required String openDate,
  }) async {
    const storage = FlutterSecureStorage();
    String? baseUrl = await storage.read(key: 'AccessUrl');
    String? token = await storage.read(key: 'LoginToken');

    if (baseUrl == null) {
      return {'success': false, 'message': '接続先URLが設定されていません'};
    }

    if (token == null) {
      return {'success': false, 'message': '端末認証トークンが見つかりません'};
    }

    final normalizedUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final url = Uri.parse('$normalizedUrl/api/v1/pos_devices/top_user_login');
    
    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'code': code,
          'pin': pin,
          'open_date': openDate,
        }),
      );

      if (response.statusCode == 200) {
        // Railsから返ってきたJSONをMapに変換して返す
        return jsonDecode(response.body);
      } else {
        return {'success': false, 'message': 'サーバーエラー: ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'message': '通信エラーが発生しました'};
    }
  }

  static Future<String> validateOperator(String code) async {
    const storage = FlutterSecureStorage();
    String? baseUrl = await storage.read(key: 'AccessUrl');
    String? token = await storage.read(key: 'LoginToken');

    if (baseUrl == null) {
      throw Exception('接続先URLが設定されていません');
    }
    if (token == null) {
      throw Exception('端末認証トークンが見つかりません');
    }

    final normalizedUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final url = Uri.parse('$normalizedUrl/api/v1/pos_devices/check_operator');

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'code': code,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['name'];
        } else {
          throw Exception(data['message'] ?? '担当者が見つかりません');
        }
      } else {
        throw Exception('サーバーエラー: ${response.statusCode}');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('通信エラーが発生しました: $e');
    }
  }
}