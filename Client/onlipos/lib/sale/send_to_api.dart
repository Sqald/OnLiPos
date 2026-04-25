import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onlipos/sale/offline_sale_repository.dart';

class SentToApi {
  static const _storage = FlutterSecureStorage();
  final OfflineSaleRepository _offlineRepo = OfflineSaleRepository();

  Future<Map<String, dynamic>> sendSale({
    required int totalAmount,
    int subtotalExTax = 0,
    int taxAmount = 0,
    required String receiptNumber,
    required int employeeId,
    required List<Map<String, dynamic>> details,
    required List<Map<String, dynamic>> payments,
  }) async {
    String? baseUrl = await _storage.read(key: 'AccessUrl');
    String? token = await _storage.read(key: 'LoginToken');

    if (baseUrl == null || token == null) {
      throw Exception('認証情報が見つかりません。ログインしてください。');
    }

    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }

    final uri = Uri.parse('$baseUrl/api/v1/sales');

    final Map<String, dynamic> requestBody = {
      'sale': {
        'total_amount': totalAmount,
        'subtotal_ex_tax': subtotalExTax,
        'tax_amount': taxAmount,
        'payment_method': payments.isNotEmpty ? payments.first['method'] : 0,
        'receipt_number': receiptNumber,
      },
      'employee_id': employeeId,
      'details': details,
      'payments': payments,
    };

    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          // サーバーから返却されたシーケンス番号をローカルに保存（次回オフライン採番の基準）
          if (responseData['next_receipt_sequence'] != null) {
            await _storage.write(
              key: 'NextReceiptSequence',
              value: responseData['next_receipt_sequence'].toString(),
            );
          }
          // オンライン会計成功時にオフラインキューの送信も試みる（バックグラウンド）
          _tryDrainInBackground();
          return responseData;
        } else {
          throw Exception('API Error: ${responseData['errors']}');
        }
      } else {
        throw Exception('HTTP Error: ${response.statusCode} ${response.body}');
      }
    } on SocketException {
      return await _saveOffline(requestBody);
    } on TimeoutException {
      return await _saveOffline(requestBody);
    }
  }

  /// オフラインキューの送信をバックグラウンドで試みる（エラーは無視）
  void _tryDrainInBackground() {
    drainOfflineQueue().catchError((_) => 0);
  }

  Future<Map<String, dynamic>> _saveOffline(Map<String, dynamic> requestBody) async {
    final receiptNumber = await _generateLocalReceiptNumber();
    (requestBody['sale'] as Map<String, dynamic>)['receipt_number'] = receiptNumber;

    await _offlineRepo.enqueue(receiptNumber, requestBody);

    return {
      'success': true,
      'offline': true,
      'receipt_number': receiptNumber,
    };
  }

  Future<String> _generateLocalReceiptNumber() async {
    final posId = await _storage.read(key: 'ReceiptPosId') ?? '0';
    final userLoginName = await _storage.read(key: 'ReceiptUserLoginName') ?? 'unknown';
    final storeAsciiName = await _storage.read(key: 'ReceiptStoreAsciiName') ?? 'unknown';
    final seq = int.tryParse(await _storage.read(key: 'NextReceiptSequence') ?? '1') ?? 1;

    await _storage.write(key: 'NextReceiptSequence', value: (seq + 1).toString());

    return '$userLoginName-$storeAsciiName-$posId-${seq.toString().padLeft(8, '0')}';
  }

  /// 未送信のオフライン会計をサーバーに一括送信する。
  /// 返り値は送信成功した件数。ネットワークエラーが発生した時点で処理を中断する。
  Future<int> drainOfflineQueue() async {
    final pending = await _offlineRepo.getPending();
    if (pending.isEmpty) return 0;

    String? baseUrl = await _storage.read(key: 'AccessUrl');
    String? token = await _storage.read(key: 'LoginToken');
    if (baseUrl == null || token == null) return 0;

    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }

    int sent = 0;
    for (final row in pending) {
      final id = row['id'] as int;
      final payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;

      try {
        final response = await http.post(
          Uri.parse('$baseUrl/api/v1/sales'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 201) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data['success'] == true) {
            await _offlineRepo.delete(id);
            if (data['next_receipt_sequence'] != null) {
              await _storage.write(
                key: 'NextReceiptSequence',
                value: data['next_receipt_sequence'].toString(),
              );
            }
            sent++;
          }
        } else if (response.statusCode == 409) {
          // 409 Conflict = 重複レシート番号。永続的に失敗するためキューから除去
          await _offlineRepo.delete(id);
        }
        // 401/403 はトークン期限切れの可能性があるためキューに残す
        // 5xx はキューに残し次回再試行
        // 5xx はキューに残し次回再試行
      } on SocketException {
        break;
      } on TimeoutException {
        break;
      } catch (_) {
        // その他のエラーはキューに残したまま次へ進む
      }
    }
    return sent;
  }
}
