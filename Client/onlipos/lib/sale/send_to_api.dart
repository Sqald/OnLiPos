import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SentToApi {
  Future<Map<String, dynamic>> sendSale({
    required int totalAmount,
    required String receiptNumber,
    required List<Map<String, dynamic>> details,
    required List<Map<String, dynamic>> payments,
  }) async {
    const storage = FlutterSecureStorage();

    // 保存されているURLとトークンを取得
    String? baseUrl = await storage.read(key: 'AccessUrl');
    String? token = await storage.read(key: 'LoginToken');

    if (baseUrl == null || token == null) {
      throw Exception('認証情報が見つかりません。ログインしてください。');
    }

    // URLの末尾スラッシュを削除して整形
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }

    final uri = Uri.parse('$baseUrl/api/v1/sales');

    // リクエストボディの構築
    final Map<String, dynamic> requestBody = {
      'sale': {
        'total_amount': totalAmount,
        'payment_method': payments.isNotEmpty ? payments.first['method'] : 0,
        'receipt_number': receiptNumber,
      },
      'details': details,
      'payments': payments,
    };

    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          // 成功時、サーバーから返却されたデータ（next_receipt_sequenceなど）を返す
          return responseData;
        } else {
          throw Exception('API Error: ${responseData['errors']}');
        }
      } else {
        throw Exception('HTTP Error: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      // ネットワークエラー等の場合は呼び出し元でハンドリング（オフライン保存処理などへ移行）
      rethrow;
    }
  }
}