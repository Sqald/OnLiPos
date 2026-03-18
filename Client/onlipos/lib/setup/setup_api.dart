import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Setup_Api {

  Future<bool> posLogin({
    required String url,
    required String userLogin,
    required String storeName,
    required String posName,
    required String posPassword,
  }) async {
    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/pos_devices/login'),
      headers: {'Content-Type': 'application/json','Accept': 'application/json',},
      body: jsonEncode({
        "pos": {
          "userName": userLogin,
          "storeName": storeName,
          "posName": posName,
          "password": posPassword,
        }
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to login: ${response.statusCode}');
    }

    final body = jsonDecode(response.body);
    if (body['success'] == true) {
      const storage = FlutterSecureStorage();
      await storage.write(key: 'LoginToken', value: body['token']);
      await storage.write(key: 'AccessUrl', value: url);
      return true;
    } else {
      return false;
    }
  }
}