// 通信断で送信できなかった会計データをSQLiteの offline_sales_queue に
// 一時保存し、後で再送するためのリポジトリ。
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:onlipos/product/database_service.dart';

class OfflineSaleRepository {
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
    });
  }

  /// 未送信のまま溜まっている会計データを登録順に取得する。
  Future<List<Map<String, dynamic>>> getPending() async {
    final db = await _db;
    return await db.query('offline_sales_queue', orderBy: 'id ASC');
  }

  /// 未送信件数を返す（画面上のバッジ表示等に使用）。
  Future<int> getPendingCount() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM offline_sales_queue',
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// 送信済みになったキューの1件を削除する。
  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('offline_sales_queue', where: 'id = ?', whereArgs: [id]);
  }
}
