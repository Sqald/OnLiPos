/// レジ開設(釣銭準備金登録)APIクライアント。
library;

import 'package:onlipos/api/pos_api_client.dart';

class OpenApi {
  /// 開設処理（釣銭準備金の登録）を行う
  Future<Map<String, dynamic>> openStore({
    required int employeeId,
    required String openDate,
    required Map<int, dynamic> cashDrawer, // 金種ごとの枚数。値はintまたはString(空文字可)
    required int totalAmount,
  }) {
    return PosApiClient.request(
      'POST',
      '/api/v1/pos_devices/open',
      body: {
        'employee_id': employeeId,
        'open_date': openDate,
        'total_amount': totalAmount,
        // JSONのキーは文字列である必要があるため変換
        'cash_drawer': cashDrawer.map((key, value) {
          final count = value is String
              ? (int.tryParse(value) ?? 0)
              : (value as int? ?? 0);
          return MapEntry(key.toString(), count);
        }),
      },
    );
  }
}
