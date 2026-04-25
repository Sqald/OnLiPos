import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onlipos/sale/sale_item.dart';

/// ホスト/クライアントモード用の転送注文（一覧表示向け、アイテムなし）
class TransferOrderEntry {
  final int id;
  final String operatorName;
  final int operatorId;
  final int totalAmount;
  final int itemCount;
  final String? tableNumber;
  final DateTime createdAt;

  TransferOrderEntry({
    required this.id,
    required this.operatorName,
    required this.operatorId,
    required this.totalAmount,
    required this.itemCount,
    this.tableNumber,
    required this.createdAt,
  });

  factory TransferOrderEntry.fromJson(Map<String, dynamic> json) {
    return TransferOrderEntry(
      id:           json['id'] as int,
      operatorName: json['operator_name'] as String,
      operatorId:   json['operator_id'] as int,
      totalAmount:  json['total_amount'] as int,
      itemCount:    json['item_count'] as int,
      tableNumber:  json['table_number'] as String?,
      createdAt:    DateTime.parse(json['created_at'] as String),
    );
  }
}

/// ホストが受け取った転送注文（アイテム込み）
class ClaimedTransferOrder {
  final int id;
  final String operatorName;
  final int operatorId;
  final int totalAmount;
  final String? tableNumber;
  final List<ScannedItem> items;

  ClaimedTransferOrder({
    required this.id,
    required this.operatorName,
    required this.operatorId,
    required this.totalAmount,
    this.tableNumber,
    required this.items,
  });
}

class TransferOrderApi {
  static const _storage = FlutterSecureStorage();

  static Future<Map<String, String>> _headers() async {
    final token = await _storage.read(key: 'LoginToken');
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  static Future<String> _baseUrl() async {
    final url = await _storage.read(key: 'AccessUrl') ?? '';
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// 未処理の転送注文一覧を取得（ホスト待ち受け用）
  static Future<List<TransferOrderEntry>> getAllTransfers() async {
    final url = await _baseUrl();
    final headers = await _headers();
    final response = await http
        .get(Uri.parse('$url/api/v1/transfer_orders'), headers: headers)
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (json['transfer_orders'] as List<dynamic>);
    return list
        .map((e) => TransferOrderEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// クライアント機からホストへ転送注文を作成する。返り値は転送ID
  static Future<int> createTransfer({
    required String operatorName,
    required int operatorId,
    required int totalAmount,
    required List<ScannedItem> items,
    String? tableNumber,
  }) async {
    final url = await _baseUrl();
    final headers = await _headers();
    final body = jsonEncode({
      'transfer_order': {
        'operator_name': operatorName,
        'operator_id':   operatorId,
        'total_amount':  totalAmount,
        'table_number':  tableNumber,
        'items':         items.map((e) => e.toJson()).toList(),
      }
    });
    final response = await http
        .post(Uri.parse('$url/api/v1/transfer_orders'), headers: headers, body: body)
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 201) throw Exception('HTTP ${response.statusCode}');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['id'] as int;
  }

  /// ホスト機が転送注文を受け取る（サーバー上から削除され、アイテムが返却される）
  static Future<ClaimedTransferOrder> claimTransfer(int id) async {
    final url = await _baseUrl();
    final headers = await _headers();
    final response = await http
        .delete(Uri.parse('$url/api/v1/transfer_orders/$id'), headers: headers)
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final order = json['transfer_order'] as Map<String, dynamic>;
    final rawItems = (order['items'] as List<dynamic>);
    return ClaimedTransferOrder(
      id:           order['id'] as int,
      operatorName: order['operator_name'] as String,
      operatorId:   order['operator_id'] as int,
      totalAmount:  order['total_amount'] as int,
      tableNumber:  order['table_number'] as String?,
      items:        rawItems
          .map((e) => ScannedItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
