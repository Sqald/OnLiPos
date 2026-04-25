import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:onlipos/product/product.dart';

class ProductLookupApi {
  static const _storage = FlutterSecureStorage();

  /// サーバにコードで商品を問い合わせる。
  /// 見つからない場合は null を返す。通信エラー時は例外を投げる。
  static Future<Product?> lookupByCode(String code) async {
    final baseUrl = await _storage.read(key: 'AccessUrl') ?? '';
    final token = await _storage.read(key: 'LoginToken') ?? '';

    final uri = Uri.parse('$baseUrl/api/v1/products/lookup')
        .replace(queryParameters: {'code': code});

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('サーバエラー: ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    if (data['success'] != true) return null;

    final p = data['product'] as Map<String, dynamic>;
    return Product(
      id: p['id'] as int,
      code: p['code'] as String,
      name: p['name'] as String,
      price: p['price'] as int,
      taxRate: (p['tax_rate'] as int?) ?? 10,
    );
  }
}
