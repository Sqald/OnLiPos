/// 店舗在庫の一覧を取得するAPIクライアント。
/// 在庫確認画面（StockCheckView）から呼び出される。
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class StockCheckApi {
  static const _storage = FlutterSecureStorage();

  /// 現在ログイン中の店舗の在庫一覧をサーバーから取得する
  static Future<Map<String, dynamic>> fetchStocks() async {
    final baseUrl = await _storage.read(key: 'AccessUrl');
    final token = await _storage.read(key: 'LoginToken');

    if (baseUrl == null || baseUrl.isEmpty) {
      return {'success': false, 'message': '接続先URLが設定されていません'};
    }
    if (token == null || token.isEmpty) {
      return {'success': false, 'message': '端末認証トークンが見つかりません'};
    }

    final normalizedUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = Uri.parse('$normalizedUrl/api/v1/store_stocks');

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
