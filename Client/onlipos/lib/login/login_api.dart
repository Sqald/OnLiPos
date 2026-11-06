/// POS端末・従業員認証まわりのAPIクライアント。
/// 業務開始ログイン、業務中の担当者PIN確認、担当者コード検証を提供する。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:onlipos/api/pos_api_client.dart';

class LoginApi {
  /// 業務開始時の従業員コード＋PINによるログイン。
  static Future<Map<String, dynamic>> userLogin({
    required String code,
    required String pin,
    required String openDate,
  }) {
    return PosApiClient.request(
      'POST',
      '/api/v1/pos_devices/top_user_login',
      body: {'code': code, 'pin': pin, 'open_date': openDate},
    );
  }

  /// 業務中の担当者PIN認証（返品・在庫入出庫等の中間承認用）。
  /// top_user_login とは異なりログイン目的ではないことを明示する。
  static Future<Map<String, dynamic>> verifyEmployee({
    required String code,
    required String pin,
  }) {
    return PosApiClient.request(
      'POST',
      '/api/v1/pos_devices/verify_employee',
      body: {'code': code, 'pin': pin},
    );
  }

  /// 担当者コードを確認し、名前・ID・権限リストを返す。オフライン時は適切なエラーを返す。
  static Future<({String name, int id, List<String> permissions})>
  validateOperator(String code) async {
    try {
      final response = await PosApiClient.send(
        'POST',
        '/api/v1/pos_devices/check_operator',
        body: {'code': code},
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        final permissions =
            (data['permissions'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        return (
          name: data['name'] as String,
          id: data['employee_id'] as int,
          permissions: permissions,
        );
      } else {
        throw Exception(data['message'] ?? '担当者が見つかりません');
      }
    } on SocketException {
      throw Exception('ネットワークに接続できません。接続を確認してください。');
    } on TimeoutException {
      throw Exception(PosApiClient.timeoutMessage);
    } on FormatException {
      throw Exception('サーバーから無効なレスポンスが返されました');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('通信エラーが発生しました: $e');
    }
  }
}
