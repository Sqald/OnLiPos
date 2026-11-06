// 通信断で送信できなかった会計データをSQLiteの offline_sales_queue に
// 一時保存し、後で再送するためのリポジトリ。
// サーバーに拒否された（再送しても成功しない）会計は削除せず failed として残し、
// 売上データが失われないようにする。
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:onlipos/product/database_service.dart';

class OfflineSaleRepository {
  static const statusPending = 'pending';
  static const statusFailed = 'failed';

  Future<Database> get _db => DatabaseService.instance.database;

  /// 未送信の会計データをキューに追加する。
  Future<void> enqueue(
    String receiptNumber,
    Map<String, dynamic> payload,
  ) async {
    final db = await _db;
    await db.insert('offline_sales_queue', {
      'receipt_number': receiptNumber,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'status': statusPending,
    });
  }

  /// 再送対象（pending）の会計データを登録順に取得する。
  Future<List<Map<String, dynamic>>> getPending() async {
    final db = await _db;
    return await db.query(
      'offline_sales_queue',
      where: 'status = ?',
      whereArgs: [statusPending],
      orderBy: 'id ASC',
    );
  }

  /// 再送対象の件数を返す（画面上のバッジ表示等に使用）。
  Future<int> getPendingCount() => _countByStatus(statusPending);

  /// サーバーに拒否され、確認が必要な会計の件数を返す。
  Future<int> getFailedCount() => _countByStatus(statusFailed);

  Future<int> _countByStatus(String status) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM offline_sales_queue WHERE status = ?',
      [status],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// 送信済みになったキューの1件を削除する。
  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('offline_sales_queue', where: 'id = ?', whereArgs: [id]);
  }

  /// キューに保存済みの会計データを書き換える（冪等キーの付与など）。
  Future<void> updatePayload(int id, Map<String, dynamic> payload) async {
    final db = await _db;
    await db.update(
      'offline_sales_queue',
      {'payload': jsonEncode(payload)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// サーバーに拒否された会計を failed にし、理由を記録する（再送対象から外す）。
  Future<void> markFailed(int id, String error) async {
    final db = await _db;
    await db.update(
      'offline_sales_queue',
      {'status': statusFailed, 'last_error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
