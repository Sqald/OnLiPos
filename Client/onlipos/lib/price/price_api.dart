import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PriceApi {
  static Future<Map<String, String>> _headers() async {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'LoginToken') ?? '';
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  static Future<String> _baseUrl() async {
    const storage = FlutterSecureStorage();
    final url = await storage.read(key: 'AccessUrl') ?? '';
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  static Future<Map<String, dynamic>> fetchStorePrices({
    required int employeeId,
    String query = '',
    int lastId = 0,
  }) async {
    try {
      final base = await _baseUrl();
      final headers = await _headers();
      final queryParams = <String, String>{
        'employee_id': employeeId.toString(),
        'last_id': lastId.toString(),
        if (query.isNotEmpty) 'q': query,
      };
      final uri = Uri.parse(
        '$base/api/v1/store_prices',
      ).replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: headers);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on SocketException {
      return {'success': false, 'message': 'ネットワークに接続できません'};
    } catch (_) {
      return {'success': false, 'message': '通信エラーが発生しました'};
    }
  }

  static Future<Map<String, dynamic>> updateStorePrice({
    required int employeeId,
    required int productId,
    required String mode,
    int? amount,
  }) async {
    try {
      final base = await _baseUrl();
      final headers = await _headers();
      final body = <String, dynamic>{
        'employee_id': employeeId,
        'product_id': productId,
        'mode': mode,
        'amount': ?amount,
      };
      final response = await http.patch(
        Uri.parse('$base/api/v1/store_prices'),
        headers: headers,
        body: jsonEncode(body),
      );
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on SocketException {
      return {'success': false, 'message': 'ネットワークに接続できません'};
    } catch (_) {
      return {'success': false, 'message': '通信エラーが発生しました'};
    }
  }
}
