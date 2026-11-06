/// 電子ジャーナル(売上・返品・レジ操作の記録)をサーバーから取得するAPIクライアント。
/// 接続先URLと認証トークンはSecureStorageから読み取る。
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onlipos/api/pos_api_client.dart';

class JournalApi {
  static const _storage = FlutterSecureStorage();

  /// GET /api/v1/journals
  /// [posId]・[date](YYYY-MM-DD)・[type] は省略可能。
  static Future<Map<String, dynamic>> fetchList({
    required int employeeId,
    int? posId,
    String? date,
    String? type,
  }) {
    return PosApiClient.request(
      'GET',
      '/api/v1/journals',
      query: {
        'employee_id': employeeId.toString(),
        if (posId != null) 'pos_id': posId.toString(),
        'date': ?date,
        'type': ?type,
      },
    );
  }

  /// GET /api/v1/journals/:id
  static Future<Map<String, dynamic>> fetchDetail({
    required int employeeId,
    required int id,
  }) {
    return PosApiClient.request(
      'GET',
      '/api/v1/journals/$id',
      query: {'employee_id': employeeId.toString()},
    );
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
