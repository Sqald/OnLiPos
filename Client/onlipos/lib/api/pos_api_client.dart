/// POS端末からサーバーAPIを呼び出すための共通クライアント。
/// SecureStorage に保存された接続先URL・端末認証トークンの読み込み、URLの組み立て、
/// 認証ヘッダーの付与、タイムアウト、JSONレスポンスのパースを一か所にまとめる。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class PosApiClient {
  static const _storage = FlutterSecureStorage();

  /// 個別指定がない場合のタイムアウト。応答がないままレジ操作が固まるのを防ぐ
  static const defaultTimeout = Duration(seconds: 15);

  static const noUrlMessage = '接続先URLが設定されていません';
  static const noTokenMessage = '端末認証トークンが見つかりません';
  static const offlineMessage = 'ネットワークに接続できません';
  static const timeoutMessage = 'サーバーから応答がありません';
  static const failedMessage = '通信エラーが発生しました';

  /// 接続先URLの末尾スラッシュを取り除く（パス連結時の "//" を防ぐ）
  static String normalizeBaseUrl(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  /// 保存済みの接続先URL（正規化済み）と端末認証トークン。
  /// 未設定なら [PosApiConfigException] を投げる
  static Future<({String baseUrl, String token})> credentials() async {
    final baseUrl = await _storage.read(key: 'AccessUrl');
    final token = await _storage.read(key: 'LoginToken');
    if (baseUrl == null || baseUrl.isEmpty) {
      throw const PosApiConfigException(noUrlMessage);
    }
    if (token == null || token.isEmpty) {
      throw const PosApiConfigException(noTokenMessage);
    }
    return (baseUrl: normalizeBaseUrl(baseUrl), token: token);
  }

  /// 認証付きでAPIを呼び出し、生のレスポンスを返す。
  /// [path] は "/api/v1/..." 形式。[body] を渡すとJSONとして送信する。
  /// 接続情報が未設定なら [PosApiConfigException]、通信失敗時は SocketException / TimeoutException 等をそのまま投げる。
  static Future<http.Response> send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Duration timeout = defaultTimeout,
  }) async {
    final creds = await credentials();
    var uri = Uri.parse('${creds.baseUrl}$path');
    if (query != null) uri = uri.replace(queryParameters: query);

    final headers = {
      'Authorization': 'Bearer ${creds.token}',
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };
    final encoded = body == null ? null : jsonEncode(body);

    final Future<http.Response> response = switch (method) {
      'GET' => http.get(uri, headers: headers),
      'POST' => http.post(uri, headers: headers, body: encoded),
      'PUT' => http.put(uri, headers: headers, body: encoded),
      'PATCH' => http.patch(uri, headers: headers, body: encoded),
      'DELETE' => http.delete(uri, headers: headers, body: encoded),
      _ => throw ArgumentError.value(method, 'method'),
    };
    return response.timeout(timeout);
  }

  /// 結果を `{'success': ..., 'message': ...}` 形式の Map で扱うAPI向けの呼び出し。
  /// 接続情報の未設定・通信失敗・JSON以外の応答もすべてエラー用の Map に変換し、例外は投げない。
  static Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Duration timeout = defaultTimeout,
  }) async {
    final http.Response response;
    try {
      response = await send(
        method,
        path,
        query: query,
        body: body,
        timeout: timeout,
      );
    } on PosApiConfigException catch (e) {
      return _error(e.message);
    } on SocketException {
      return _error(offlineMessage);
    } on TimeoutException {
      return _error(timeoutMessage);
    } on http.ClientException {
      return _error(offlineMessage);
    } catch (_) {
      return _error(failedMessage);
    }
    return parseJson(response);
  }

  /// レスポンスボディをJSONオブジェクトとしてパースする。失敗時はエラー用の Map を返す
  static Map<String, dynamic> parseJson(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // JSON 以外（HTMLのエラーページ等）はステータスコードで知らせる
    }
    return _error('サーバーエラー: ${response.statusCode}');
  }

  static Map<String, dynamic> _error(String message) => {
    'success': false,
    'message': message,
  };
}

/// 接続先URL・端末認証トークンが未設定（未セットアップ）であることを表す例外
class PosApiConfigException implements Exception {
  const PosApiConfigException(this.message);
  final String message;

  // 従来の Exception(message) と同じ表示になるようにする
  @override
  String toString() => 'Exception: $message';
}
