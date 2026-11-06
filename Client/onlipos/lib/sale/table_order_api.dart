import 'dart:convert';
import 'package:onlipos/api/pos_api_client.dart';
import 'sale_item.dart';

/// 飲食店モード用：サーバー上のテーブル注文 API ラッパー。
/// 同一店舗内の全 POS で注文データを共有する。
class TableOrderApi {
  /// 店舗内共有データの操作は短めのタイムアウトで打ち切る
  static const _timeout = Duration(seconds: 5);

  // テーブル番号は入力値のため、パスに埋め込む際はエンコードして別パスへの混入を防ぐ
  static String _tablePath(String tableNumber) =>
      '/api/v1/table_orders/${Uri.encodeComponent(tableNumber)}';

  /// アクティブ（アイテムがある）テーブル番号の一覧を取得する。
  static Future<List<String>> getActiveTables() async {
    final response = await PosApiClient.send(
      'GET',
      '/api/v1/table_orders',
      timeout: _timeout,
    );
    if (response.statusCode == 200) {
      final List list = jsonDecode(response.body) as List;
      return list.map((e) => e['table_number'].toString()).toList();
    }
    throw Exception('table_orders index failed: ${response.statusCode}');
  }

  /// 指定テーブルの ScannedItem 一覧を取得する。存在しなければ空リスト。
  static Future<List<ScannedItem>> getItems(String tableNumber) async {
    final response = await PosApiClient.send(
      'GET',
      _tablePath(tableNumber),
      timeout: _timeout,
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final List rawItems = (body['items'] as List?) ?? [];
      return rawItems
          .map((j) => ScannedItem.fromJson(j as Map<String, dynamic>))
          .toList();
    }
    throw Exception('table_orders show failed: ${response.statusCode}');
  }

  /// 指定テーブルのアイテムを保存する（upsert）。
  static Future<void> saveItems(
    String tableNumber,
    List<ScannedItem> items,
  ) async {
    await PosApiClient.send(
      'PUT',
      _tablePath(tableNumber),
      body: {'items': items.map((e) => e.toJson()).toList()},
      timeout: _timeout,
    );
  }

  /// 指定テーブルのデータを削除する（会計完了・全消去時）。
  static Future<void> clearTable(String tableNumber) async {
    await PosApiClient.send(
      'DELETE',
      _tablePath(tableNumber),
      timeout: _timeout,
    );
  }
}
