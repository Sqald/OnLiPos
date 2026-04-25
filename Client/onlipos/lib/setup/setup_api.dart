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

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Failed to login: ${response.statusCode}');
    }

    if (body['success'] == true) {
      const storage = FlutterSecureStorage();
      await storage.write(key: 'LoginToken', value: body['token']);
      await storage.write(key: 'AccessUrl', value: url);
      if (body['pos_id'] != null) {
        await storage.write(key: 'ReceiptPosId', value: body['pos_id'].toString());
      }
      if (body['user_login_name'] != null) {
        await storage.write(key: 'ReceiptUserLoginName', value: body['user_login_name'].toString());
      }
      if (body['store_ascii_name'] != null) {
        await storage.write(key: 'ReceiptStoreAsciiName', value: body['store_ascii_name'].toString());
      }
      if (body['next_receipt_sequence'] != null) {
        await storage.write(key: 'NextReceiptSequence', value: body['next_receipt_sequence'].toString());
      }
      return true;
    } else {
      return false;
    }
  }
}
