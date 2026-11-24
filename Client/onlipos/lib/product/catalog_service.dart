/// 商品以外のマスタ（自動値引き・価格/税率の予約変更・契約の設定）を端末に保存・参照する。
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onlipos/product/database_service.dart';
import 'package:onlipos/product/scheduled_change.dart';
import 'package:onlipos/sale/cart_pricing.dart';
import 'package:onlipos/sale/promotion.dart';
import 'package:sqflite/sqflite.dart';

class CatalogService {
  CatalogService._();
  static final instance = CatalogService._();

  static const _storage = FlutterSecureStorage();
  List<ScheduledChange>? _changes;
  List<Promotion>? _promotions;
  Map<String, dynamic>? _settings;

  static Future<void> saveMeta(
    DatabaseExecutor db,
    Map<String, dynamic> response,
  ) async {
    for (final key in const ['promotions', 'scheduled_changes', 'settings']) {
      if (response[key] == null) continue;
      await db.insert('catalog_meta', {
        'key': key,
        'value': jsonEncode(response[key]),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // 同期後に読み直す
  void invalidate() {
    _changes = null;
    _promotions = null;
    _settings = null;
  }

  Future<dynamic> _read(String key) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      'catalog_meta',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : jsonDecode(rows.first['value'] as String);
  }

  Future<List<ScheduledChange>> scheduledChanges() async =>
      _changes ??= ((await _read('scheduled_changes') as List<dynamic>?) ?? [])
          .map((e) => ScheduledChange.fromMap(e as Map<String, dynamic>))
          .toList();

  Future<List<Promotion>> promotions() async =>
      _promotions ??= ((await _read('promotions') as List<dynamic>?) ?? [])
          .map((e) => Promotion.fromMap(e as Map<String, dynamic>))
          .toList();

  Future<Map<String, dynamic>> settings() async =>
      _settings ??= (await _read('settings') as Map<String, dynamic>?) ?? {};

  Future<CartPricing> cartPricing() async => CartPricing(
    promotions: await promotions(),
    rounding: await _storage.read(key: 'TaxRoundingMethod') ?? 'round_down',
  );

  /// レシート印字に使う設定を、従来の保存場所にも反映する
  static Future<void> saveSettings(Map<String, dynamic>? settings) async {
    if (settings == null) return;
    await _storage.write(
      key: 'InvoiceRegistrationNumber',
      value: settings['invoice_registration_number']?.toString() ?? '',
    );
    await _storage.write(
      key: 'TaxRoundingMethod',
      value: settings['tax_rounding_method']?.toString() ?? 'round_down',
    );
  }
}
