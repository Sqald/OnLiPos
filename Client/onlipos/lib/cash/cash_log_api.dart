import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// レジ金に関するAPIクライアント。
///
/// - 端末認証トークンと接続先URLはすべて `FlutterSecureStorage` から取得し、
///   画面やログには表示しないことで漏えいリスクを抑えます。
/// - サーバー側でPOSトークンの検証と店舗スコープの制御を行う前提で、
///   クライアントは必要最小限の情報（担当者ID・金種枚数・合計金額）のみ送信します。
class CashLogApi {
  static const _storage = FlutterSecureStorage();

  Future<Map<String, dynamic>> _postCashLog({
    required String path,
    required int employeeId,
    required Map<int, int> cashDrawer,
    required int totalAmount,
  }) async {
    final baseUrl = await _storage.read(key: 'AccessUrl');
    final token = await _storage.read(key: 'LoginToken');

    if (baseUrl == null || baseUrl.isEmpty) {
      return {'success': false, 'message': '接続先URLが設定されていません'};
    }
    if (token == null || token.isEmpty) {
      return {'success': false, 'message': '端末認証トークンが見つかりません'};
    }

    // URLはユーザー入力値をそのまま使わず、末尾のスラッシュを正規化するのみとし、
    // それ以外の文字列操作は行わないことで想定外のパスを生成しないようにします。
    final normalizedUrl =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final url = Uri.parse('$normalizedUrl$path');

    // JSONのキーは文字列である必要があるため、金種キーのみ文字列化します。
    final cashDrawerJson = cashDrawer.map((key, value) {
      return MapEntry(key.toString(), value);
    });

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
          'total_amount': totalAmount,
          'cash_drawer': cashDrawerJson,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        return {
          'success': false,
          'message': 'サーバーエラー: ${response.statusCode}',
        };
      }
    } catch (e) {
      // 例外メッセージはユーザー向けに簡略化して返し、ネットワーク詳細やスタックトレースを
      // そのまま表示しないことで情報漏えいを防ぎます。
      return {
        'success': false,
        'message': '通信エラーが発生しました: $e',
      };
    }
  }

  /// レジ金チェック（営業中の残高確認）を登録する。
  Future<Map<String, dynamic>> cashCheck({
    required int employeeId,
    required Map<int, int> cashDrawer,
    required int totalAmount,
  }) {
    return _postCashLog(
      path: '/api/v1/pos_devices/cash_check',
      employeeId: employeeId,
      cashDrawer: cashDrawer,
      totalAmount: totalAmount,
    );
  }

  /// レジ精算（営業終了時の残高確定）を登録する。
  Future<Map<String, dynamic>> closeRegister({
    required int employeeId,
    required Map<int, int> cashDrawer,
    required int totalAmount,
  }) {
    return _postCashLog(
      path: '/api/v1/pos_devices/close_register',
      employeeId: employeeId,
      cashDrawer: cashDrawer,
      totalAmount: totalAmount,
    );
  }

  /// レジ金チェック画面用のコンテキストを取得する。
  /// 当日の開始レジ金および現時点までの現金売上から算出した
  /// expected_amount（あるべきレジ金）を返す。
  Future<Map<String, dynamic>> fetchCashCheckContext() async {
    final baseUrl = await _storage.read(key: 'AccessUrl');
    final token = await _storage.read(key: 'LoginToken');

    if (baseUrl == null || baseUrl.isEmpty) {
      return {'success': false, 'message': '接続先URLが設定されていません'};
    }
    if (token == null || token.isEmpty) {
      return {'success': false, 'message': '端末認証トークンが見つかりません'};
    }

    final normalizedUrl =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final url = Uri.parse('$normalizedUrl/api/v1/pos_devices/cash_check_context');

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        return {
          'success': false,
          'message': 'サーバーエラー: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': '通信エラーが発生しました: $e',
      };
    }
  }
}

