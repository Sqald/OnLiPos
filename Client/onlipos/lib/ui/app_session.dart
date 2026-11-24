/// 画面のフッターに表示する、いまの業務の状態（店舗・担当者・営業日・通信・未送信件数）。
/// 表示のためだけに使い、権限の判定には使わない。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onlipos/sale/offline_sale_repository.dart';

class AppSession extends ChangeNotifier {
  AppSession._();
  static final instance = AppSession._();

  String? storeName;
  String? operatorName;
  DateTime? businessDate;

  /// 直近の通信の成否（まだ通信していなければ null）
  bool? online;
  int pendingCount = 0;
  int failedCount = 0;

  /// 端末に保存した店舗名などを読み込む
  Future<void> loadStore() async {
    try {
      const storage = FlutterSecureStorage();
      storeName = await storage.read(key: 'StoreName');
    } catch (_) {
      // 読み込めなくても業務には影響しない
    }
    notifyListeners();
  }

  void startBusiness({required String operatorName, required DateTime date}) {
    this.operatorName = operatorName;
    businessDate = date;
    loadStore();
    refreshCounts();
  }

  void endBusiness() {
    operatorName = null;
    businessDate = null;
    notifyListeners();
  }

  void reportConnection(bool ok) {
    if (online == ok) return;
    online = ok;
    notifyListeners();
  }

  /// 未送信・送信できなかった会計の件数を数え直す
  Future<void> refreshCounts() async {
    try {
      final repository = OfflineSaleRepository();
      final pending = await repository.getPendingCount();
      final failed = await repository.getFailedCount();
      if (pending == pendingCount && failed == failedCount) return;
      pendingCount = pending;
      failedCount = failed;
      notifyListeners();
    } catch (_) {
      // 端末のデータベースを開けない場合は表示しない
    }
  }
}
