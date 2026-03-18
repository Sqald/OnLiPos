
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ProvisioningApi {
  static Future<Map<String, dynamic>> getProvisioning() async {
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
    final url = Uri.parse('$normalizedUrl/api/v1/pos_devices/provisioning');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
        body: jsonEncode({}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['provisioning'];
        } else {
          throw Exception(data['message'] ?? 'プロビジョニングデータの取得に失敗しました');
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
