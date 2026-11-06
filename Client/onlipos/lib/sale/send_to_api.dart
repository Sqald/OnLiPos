// 会計データをサーバー（/api/v1/sales）へ送信するAPIクライアント。
// 通信断・タイムアウト時はオフラインキュー（OfflineSaleRepository）に保存し、
// ローカル採番したレシート番号を発行して後で再送する。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:onlipos/api/pos_api_client.dart';
import 'package:onlipos/sale/offline_sale_repository.dart';

class SentToApi {
  static const _storage = FlutterSecureStorage();
  final OfflineSaleRepository _offlineRepo = OfflineSaleRepository();

  static const _noCredentialsMessage = '認証情報が見つかりません。ログインしてください。';

  // 接続情報が未設定の場合は「ログインしてください」の案内付きで例外にする
  static Future<http.Response> _post(String path, Object body) async {
    try {
      return await PosApiClient.send('POST', path, body: body);
    } on PosApiConfigException {
      throw Exception(_noCredentialsMessage);
    }
  }

  // 会計ごとの冪等キー（UUID v4）。タイムアウト後の再送でも同じ値を送ることで、
  // サーバー側で登録済みの会計と照合され、二重計上されない。
  @visibleForTesting
  static String newRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  // 登録成功（新規 201 / 冪等キーによる登録済み 200）のレスポンスか
  static bool _isRegistered(http.Response response) =>
      response.statusCode == 201 || response.statusCode == 200;

  /// 会計をサーバーに送信する。通信不可時はオフラインキューに保存してフォールバックする。
  Future<Map<String, dynamic>> sendSale({
    required int totalAmount,
    int subtotalExTax = 0,
    int taxAmount = 0,
    required String receiptNumber,
    required int employeeId,
    required List<Map<String, dynamic>> details,
    required List<Map<String, dynamic>> payments,
    String? customerGender,
    String? customerAgeGroup,
  }) async {
    final Map<String, dynamic> requestBody = {
      'client_request_id': newRequestId(),
      'sale': {
        'total_amount': totalAmount,
        'subtotal_ex_tax': subtotalExTax,
        'tax_amount': taxAmount,
        'payment_method': payments.isNotEmpty ? payments.first['method'] : 0,
        'receipt_number': receiptNumber,
        // 販売時刻。オフライン後送でも実際の会計時刻がサーバーに記録される
        'sold_at': DateTime.now().toIso8601String(),
        // 客層キー（性別・年代）。未選択の場合は送信しない
        'customer_gender': ?customerGender,
        'customer_age_group': ?customerAgeGroup,
      },
      'employee_id': employeeId,
      'details': details,
      'payments': payments,
    };

    try {
      final response = await _post('/api/v1/sales', requestBody);

      if (_isRegistered(response)) {
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

  /// 領収書発行を記録する（発行履歴がジャーナルに残り、2回目以降は再発行になる）。
  Future<Map<String, dynamic>> issueReceipt({
    required int saleId,
    required int employeeId,
    String? addressee,
    String? purpose,
  }) async {
    final response = await _post('/api/v1/sales/$saleId/issue_receipt', {
      'employee_id': employeeId,
      if (addressee != null && addressee.isNotEmpty) 'addressee': addressee,
      if (purpose != null && purpose.isNotEmpty) 'purpose': purpose,
    });

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// オフラインキューの送信をバックグラウンドで試みる（エラーは無視）
  void _tryDrainInBackground() {
    drainOfflineQueue().catchError((_) => 0);
  }

  // ローカル採番したレシート番号を付与してオフラインキューに保存する
  Future<Map<String, dynamic>> _saveOffline(
    Map<String, dynamic> requestBody,
  ) async {
    final receiptNumber = await _generateLocalReceiptNumber();
    (requestBody['sale'] as Map<String, dynamic>)['receipt_number'] =
        receiptNumber;

    await _offlineRepo.enqueue(receiptNumber, requestBody);

    return {'success': true, 'offline': true, 'receipt_number': receiptNumber};
  }

  // 「ログイン名-店舗名-POS番号-連番」形式でオフライン用レシート番号を生成する
  Future<String> _generateLocalReceiptNumber() async {
    final posId = await _storage.read(key: 'ReceiptPosId') ?? '0';
    final userLoginName =
        await _storage.read(key: 'ReceiptUserLoginName') ?? 'unknown';
    final storeAsciiName =
        await _storage.read(key: 'ReceiptStoreAsciiName') ?? 'unknown';
    final seq =
        int.tryParse(await _storage.read(key: 'NextReceiptSequence') ?? '1') ??
        1;

    await _storage.write(
      key: 'NextReceiptSequence',
      value: (seq + 1).toString(),
    );

    return '$userLoginName-$storeAsciiName-$posId-${seq.toString().padLeft(8, '0')}';
  }

  /// 未送信のオフライン会計をサーバーに一括送信する。
  /// 返り値は送信成功した件数。ネットワークエラーが発生した時点で処理を中断する。
  ///
  /// - 送信済みかどうかはサーバーが冪等キー（client_request_id）で照合するため、
  ///   タイムアウトで結果が分からなかった会計を再送しても二重計上されない。
  /// - サーバーに拒否された会計（再送しても成功しない 4xx）は削除せず failed として残す。
  Future<int> drainOfflineQueue() async {
    final pending = await _offlineRepo.getPending();
    if (pending.isEmpty) return 0;

    int sent = 0;
    for (final row in pending) {
      final id = row['id'] as int;
      final payload =
          jsonDecode(row['payload'] as String) as Map<String, dynamic>;

      // 旧バージョンで保存された会計には冪等キーがないため、送信前に付与して保存する
      if (payload['client_request_id'] == null) {
        payload['client_request_id'] = newRequestId();
        await _offlineRepo.updatePayload(id, payload);
      }

      try {
        final response = await PosApiClient.send(
          'POST',
          '/api/v1/sales',
          body: payload,
        );

        if (_isRegistered(response)) {
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
        } else if (isPermanentFailure(response.statusCode)) {
          // 409（レシート番号重複）・422（入力不正）等は再送しても成功しないため、
          // 再送対象から外して failed として残す（売上データは削除しない）
          await _offlineRepo.markFailed(id, _errorSummary(response));
        }
        // 401/403（トークン・権限）、408/429、5xx はキューに残し次回再試行
      } on PosApiConfigException {
        // 未セットアップ（接続先・トークンなし）の場合は送信しようがないので中断
        break;
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

  // 再送しても結果が変わらない 4xx か（認証・権限・タイムアウト・レート制限は除く）
  @visibleForTesting
  static bool isPermanentFailure(int status) =>
      status >= 400 &&
      status < 500 &&
      !const {401, 403, 408, 429}.contains(status);

  // failed として記録するエラー内容（サーバーのエラーメッセージ、なければステータスコード）
  static String _errorSummary(http.Response response) {
    final data = PosApiClient.parseJson(response);
    final errors = data['errors'];
    if (errors is List && errors.isNotEmpty) {
      return 'HTTP ${response.statusCode}: ${errors.join(', ')}';
    }
    return 'HTTP ${response.statusCode}: ${data['message'] ?? ''}';
  }
}
