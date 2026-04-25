import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'sale_item.dart';

/// 飲食店モード用：サーバー上のテーブル注文 API ラッパー。
/// 同一店舗内の全 POS で注文データを共有する。
class TableOrderApi {
  static const _storage = FlutterSecureStorage();

  static Future<Map<String, String>> _headers() async {
    final token = await _storage.read(key: 'LoginToken') ?? '';
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<String> _baseUrl() async {
    final raw = await _storage.read(key: 'AccessUrl') ?? '';
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  /// アクティブ（アイテムがある）テーブル番号の一覧を取得する。
  static Future<List<String>> getActiveTables() async {
    final base = await _baseUrl();
    final headers = await _headers();
    final response = await http
        .get(Uri.parse('$base/api/v1/table_orders'), headers: headers)
        .timeout(const Duration(seconds: 5));
    if (response.statusCode == 200) {
      final List list = jsonDecode(response.body) as List;
      return list.map((e) => e['table_number'].toString()).toList();
    }
    throw Exception('table_orders index failed: ${response.statusCode}');
  }

  /// 指定テーブルの ScannedItem 一覧を取得する。存在しなければ空リスト。
  static Future<List<ScannedItem>> getItems(String tableNumber) async {
    final base = await _baseUrl();
    final headers = await _headers();
    final response = await http
        .get(Uri.parse('$base/api/v1/table_orders/$tableNumber'), headers: headers)
        .timeout(const Duration(seconds: 5));
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
      String tableNumber, List<ScannedItem> items) async {
    final base = await _baseUrl();
    final headers = await _headers();
    await http
        .put(
          Uri.parse('$base/api/v1/table_orders/$tableNumber'),
          headers: headers,
          body: jsonEncode({'items': items.map((e) => e.toJson()).toList()}),
        )
        .timeout(const Duration(seconds: 5));
  }

  /// 指定テーブルのデータを削除する（会計完了・全消去時）。
  static Future<void> clearTable(String tableNumber) async {
    final base = await _baseUrl();
    final headers = await _headers();
    await http
        .delete(
          Uri.parse('$base/api/v1/table_orders/$tableNumber'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 5));
  }
}
