import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class JournalApi {
  static const _storage = FlutterSecureStorage();

  static Future<String?> _baseUrl() async {
    final url = await _storage.read(key: 'AccessUrl');
    if (url == null || url.isEmpty) return null;
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  static Future<String?> _token() => _storage.read(key: 'LoginToken');

  static Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
  };

  /// GET /api/v1/journals
  /// [posId]・[date](YYYY-MM-DD)・[type] は省略可能。
  static Future<Map<String, dynamic>> fetchList({
    required int employeeId,
    int? posId,
    String? date,
    String? type,
  }) async {
    final base = await _baseUrl();
    final token = await _token();
    if (base == null) return {'success': false, 'message': '接続先URLが設定されていません'};
    if (token == null) return {'success': false, 'message': '端末認証トークンが見つかりません'};

    final params = {'employee_id': employeeId.toString()};
    if (posId != null) params['pos_id'] = posId.toString();
    if (date != null) params['date'] = date;
    if (type != null) params['type'] = type;

    final url = Uri.parse(
      '$base/api/v1/journals',
    ).replace(queryParameters: params);
    try {
      final resp = await http.get(url, headers: _headers(token));
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } on SocketException {
      return {'success': false, 'message': 'ネットワークに接続できません'};
    } catch (_) {
      return {'success': false, 'message': '通信エラーが発生しました'};
    }
  }

  /// GET /api/v1/journals/:id
  static Future<Map<String, dynamic>> fetchDetail({
    required int employeeId,
    required int id,
  }) async {
    final base = await _baseUrl();
    final token = await _token();
    if (base == null) return {'success': false, 'message': '接続先URLが設定されていません'};
    if (token == null) return {'success': false, 'message': '端末認証トークンが見つかりません'};

    final url = Uri.parse('$base/api/v1/journals/$id?employee_id=$employeeId');
    try {
      final resp = await http.get(url, headers: _headers(token));
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } on SocketException {
      return {'success': false, 'message': 'ネットワークに接続できません'};
    } catch (_) {
      return {'success': false, 'message': '通信エラーが発生しました'};
    }
  }

  /// 自店舗の POS 端末一覧を返す（端末フィルタ用）。
  /// sales/summary と同じエンドポイントは存在しないので、
  /// /api/v1/pos_devices から簡易取得できないため、ここでは
  /// ローカルの SecureStorage から pos_id だけ取り出して使う。
  static Future<({int posId, String posName})> currentPos() async {
    final id =
        int.tryParse(await _storage.read(key: 'ReceiptPosId') ?? '') ?? 0;
    final name = await _storage.read(key: 'ReceiptStoreAsciiName') ?? 'このPOS';
    return (posId: id, posName: name);
  }
}
