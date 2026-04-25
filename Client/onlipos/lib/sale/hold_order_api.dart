import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'sale_item.dart';

/// サーバーから取得した保留情報（アイテムなし、一覧表示用）。
class HoldOrderEntry {
  final int holdNumber;
  final String operatorName;
  final int operatorId;
  final int totalAmount;
  final DateTime createdAt;

  const HoldOrderEntry({
    required this.holdNumber,
    required this.operatorName,
    required this.operatorId,
    required this.totalAmount,
    required this.createdAt,
  });
}

/// サーバーから取得した保留データ（呼び出し時、アイテムあり）。
class RecalledHoldOrder {
  final int holdNumber;
  final String operatorName;
  final int operatorId;
  final int totalAmount;
  final List<ScannedItem> items;

  const RecalledHoldOrder({
    required this.holdNumber,
    required this.operatorName,
    required this.operatorId,
    required this.totalAmount,
    required this.items,
  });
}

/// 小売店モード用：サーバー上の保留注文 API ラッパー。
/// 同一店舗内の全 POS で保留データを共有する。
class HoldOrderApi {
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

  /// この店舗の保留一覧を取得する（アイテムなし、表示用）。
  static Future<List<HoldOrderEntry>> getAllHolds() async {
    final base = await _baseUrl();
    final headers = await _headers();
    final response = await http
        .get(Uri.parse('$base/api/v1/hold_orders'), headers: headers)
        .timeout(const Duration(seconds: 5));
    if (response.statusCode == 200) {
      final List list = jsonDecode(response.body) as List;
      return list.map((e) {
        return HoldOrderEntry(
          holdNumber: (e['hold_number'] as num).toInt(),
          operatorName: e['operator_name'].toString(),
          operatorId: (e['operator_id'] as num).toInt(),
          totalAmount: (e['total_amount'] as num).toInt(),
          createdAt: DateTime.parse(e['created_at'].toString()),
        );
      }).toList();
    }
    throw Exception('hold_orders index failed: ${response.statusCode}');
  }

  /// 新規保留を作成し、サーバーが割り当てた保留番号を返す。
  static Future<int> createHold({
    required String operatorName,
    required int operatorId,
    required int totalAmount,
    required List<ScannedItem> items,
  }) async {
    final base = await _baseUrl();
    final headers = await _headers();
    final response = await http
        .post(
          Uri.parse('$base/api/v1/hold_orders'),
          headers: headers,
          body: jsonEncode({
            'operator_name': operatorName,
            'operator_id': operatorId,
            'total_amount': totalAmount,
            'items': items.map((e) => e.toJson()).toList(),
          }),
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode == 201) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (body['hold_number'] as num).toInt();
    }
    throw Exception('hold_orders create failed: ${response.statusCode}');
  }

  /// 指定番号の保留を取り出し（サーバーから削除）、内容を返す。
  /// 存在しない場合は null を返す。
  static Future<RecalledHoldOrder?> recallHold(int holdNumber) async {
    final base = await _baseUrl();
    final headers = await _headers();
    final response = await http
        .delete(
          Uri.parse('$base/api/v1/hold_orders/$holdNumber'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final List rawItems = (body['items'] as List?) ?? [];
      return RecalledHoldOrder(
        holdNumber: (body['hold_number'] as num).toInt(),
        operatorName: body['operator_name'].toString(),
        operatorId: (body['operator_id'] as num).toInt(),
        totalAmount: (body['total_amount'] as num).toInt(),
        items: rawItems
            .map((j) => ScannedItem.fromJson(j as Map<String, dynamic>))
            .toList(),
      );
    }
    if (response.statusCode == 404) return null;
    throw Exception('hold_orders destroy failed: ${response.statusCode}');
  }
}
