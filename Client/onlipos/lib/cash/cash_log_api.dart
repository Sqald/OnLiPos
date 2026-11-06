import 'package:onlipos/api/pos_api_client.dart';

/// レジ金に関するAPIクライアント。
///
/// - 端末認証トークンと接続先URLは PosApiClient が `FlutterSecureStorage` から取得し、
///   画面やログには表示しないことで漏えいリスクを抑えます。
/// - サーバー側でPOSトークンの検証と店舗スコープの制御を行う前提で、
///   クライアントは必要最小限の情報（担当者ID・金種枚数・合計金額）のみ送信します。
class CashLogApi {
  // 金種別枚数と合計金額をレジ金チェック/精算共通のフォーマットでPOSTする共通処理
  Future<Map<String, dynamic>> _postCashLog({
    required String path,
    required int employeeId,
    required Map<int, int> cashDrawer,
    required int totalAmount,
  }) {
    return PosApiClient.request(
      'POST',
      path,
      body: {
        'employee_id': employeeId,
        'total_amount': totalAmount,
        // JSONのキーは文字列である必要があるため、金種キーのみ文字列化します。
        'cash_drawer': cashDrawer.map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      },
    );
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

  /// レジ金途中回収を登録する。
  Future<Map<String, dynamic>> cashPickup({
    required int employeeId,
    required int amount,
    String? reason,
  }) {
    return PosApiClient.request(
      'POST',
      '/api/v1/pos_devices/cash_pickup',
      body: {
        'employee_id': employeeId,
        'amount': amount,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
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

  /// レジ入出金（釣銭補充・雑入金・雑出金・途中回収）を登録する。
  /// kind: 'replenishment'(釣銭補充) / 'misc_in'(雑入金) / 'misc_out'(雑出金) / 'pickup'(途中回収)
  Future<Map<String, dynamic>> cashMovement({
    required int employeeId,
    required String kind,
    required int amount,
    String? reason,
  }) {
    return PosApiClient.request(
      'POST',
      '/api/v1/cash_movements',
      body: {
        'employee_id': employeeId,
        'kind': kind,
        'amount': amount,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
  }

  /// 点検（X）/ 精算（Z）レポートの集計データを取得する。
  /// zNumber を省略すると現在の open セッションの点検レポート、
  /// 指定すると精算済みセッションの Z レポート（再印字用）を返す。
  Future<Map<String, dynamic>> fetchRegisterReport({
    required int employeeId,
    int? zNumber,
  }) {
    return PosApiClient.request(
      'GET',
      '/api/v1/pos_devices/register_report',
      query: {
        'employee_id': employeeId.toString(),
        if (zNumber != null) 'z_number': zNumber.toString(),
      },
    );
  }

  /// レジ金チェック画面用のコンテキストを取得する。
  /// 当日の開始レジ金および現時点までの現金売上から算出した
  /// expected_amount（あるべきレジ金）を返す。
  Future<Map<String, dynamic>> fetchCashCheckContext() {
    return PosApiClient.request(
      'GET',
      '/api/v1/pos_devices/cash_check_context',
    );
  }
}
