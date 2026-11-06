/// 端末プロビジョニングAPIクライアント。ハードウェア設定・店舗情報など
/// サーバー側で管理する端末設定を取得する。
library;

import 'dart:convert';

import 'package:onlipos/api/pos_api_client.dart';

class ProvisioningApi {
  /// サーバーから端末のプロビジョニングデータ(ハードウェア設定・店舗情報)を取得する
  static Future<Map<String, dynamic>> getProvisioning() async {
    try {
      final response = await PosApiClient.send(
        'POST',
        '/api/v1/pos_devices/provisioning',
        body: const <String, dynamic>{},
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
