import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OpenApi {
  /// 開設処理（釣銭準備金の登録）を行う
  Future<Map<String, dynamic>> openStore({
    required int employeeId,
    required String openDate,
    required Map<int, dynamic> cashDrawer, // 金種ごとの枚数。値はintまたはString(空文字可)
    required int totalAmount,
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
    final url = Uri.parse('$normalizedUrl/api/v1/pos_devices/open');

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
          'open_date': openDate,
          'total_amount': totalAmount,
          // JSONのキーは文字列である必要があるため変換
          'cash_drawer': cashDrawer.map((key, value) {
            final count = value is String ? (int.tryParse(value) ?? 0) : (value as int? ?? 0);
            return MapEntry(key.toString(), count);
          }),
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {'success': false, 'message': 'サーバーエラー: ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'message': '通信エラーが発生しました: $e'};
    }
  }
}