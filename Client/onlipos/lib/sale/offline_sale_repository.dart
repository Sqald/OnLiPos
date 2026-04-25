import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:onlipos/product/database_service.dart';

class OfflineSaleRepository {
  Future<Database> get _db => DatabaseService.instance.database;

  Future<void> enqueue(String receiptNumber, Map<String, dynamic> payload) async {
    final db = await _db;
    await db.insert('offline_sales_queue', {
      'receipt_number': receiptNumber,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getPending() async {
    final db = await _db;
    return await db.query('offline_sales_queue', orderBy: 'id ASC');
  }

  Future<int> getPendingCount() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM offline_sales_queue');
    return (result.first['count'] as int?) ?? 0;
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('offline_sales_queue', where: 'id = ?', whereArgs: [id]);
  }
}
