import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LoginApi {
  static Map<String, dynamic> _parseResponse(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return {'success': false, 'message': 'サーバーエラー: ${response.statusCode}'};
    }
  }

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
      return _parseResponse(response);
    } catch (e) {
      return {'success': false, 'message': '通信エラーが発生しました'};
    }
  }

  /// 業務中の担当者PIN認証（返品・在庫入出庫等の中間承認用）。
  /// top_user_login とは異なりログイン目的ではないことを明示する。
  static Future<Map<String, dynamic>> verifyEmployee({
    required String code,
    required String pin,
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
    final url = Uri.parse('$normalizedUrl/api/v1/pos_devices/verify_employee');

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'code': code, 'pin': pin}),
      );
      return _parseResponse(response);
    } on SocketException {
      return {'success': false, 'message': 'ネットワークに接続できません'};
    } catch (e) {
      return {'success': false, 'message': '通信エラーが発生しました'};
    }
  }

  /// 担当者コードを確認し、名前とIDを返す。オフライン時は適切なエラーを返す。
  static Future<({String name, int id})> validateOperator(String code) async {
    const storage = FlutterSecureStorage();
    String? baseUrl = await storage.read(key: 'AccessUrl');
    String? token = await storage.read(key: 'LoginToken');

    if (baseUrl == null) throw Exception('接続先URLが設定されていません');
    if (token == null) throw Exception('端末認証トークンが見つかりません');

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
        body: jsonEncode({'code': code}),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        return (name: data['name'] as String, id: data['employee_id'] as int);
      } else {
        throw Exception(data['message'] ?? '担当者が見つかりません');
      }
    } on SocketException {
      throw Exception('ネットワークに接続できません。接続を確認してください。');
    } on FormatException {
      throw Exception('サーバーから無効なレスポンスが返されました');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('通信エラーが発生しました: $e');
    }
  }
}
