/// 客用表示（ブラウザの別画面）へカートの内容を送る。
/// 設定画面で有効にした端末だけが送信し、会計操作を待たせないよう結果は待たない。
library;

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onlipos/sale/sale_extras_api.dart';
import 'package:onlipos/sale/sale_item.dart';

class CustomerDisplay {
  static const storageKey = 'CustomerDisplayEnabled';
  static const _storage = FlutterSecureStorage();
  static Timer? _timer;
  static bool? _enabled;

  static Future<bool> isEnabled() async =>
      _enabled ??= await _storage.read(key: storageKey) == 'true';

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _storage.write(key: storageKey, value: value.toString());
  }

  /// 連続した変更はまとめて1回だけ送る
  static void update(List<ScannedItem> items, int total) {
    // 無効な端末では何もしない（未確認なら確認してから送る）
    if (_enabled == false) return;
    final payload = items.reversed
        .map(
          (i) => {
            'name': i.bundleName ?? i.product.name,
            'quantity': i.quantity,
            'subtotal': i.subtotal,
          },
        )
        .toList();
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), () async {
      if (!await isEnabled()) return;
      await SaleExtrasApi.updateCustomerDisplay(items: payload, total: total);
    });
  }
}
