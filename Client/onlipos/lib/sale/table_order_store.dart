import 'sale_item.dart';

/// 飲食店モード用：テーブルごとのスキャン済み商品をアプリ内メモリで保持するシングルトン。
/// アプリが終了すると消える（永続化なし）。
class TableOrderStore {
  static final TableOrderStore _instance = TableOrderStore._internal();
  factory TableOrderStore() => _instance;
  TableOrderStore._internal();

  final Map<String, List<ScannedItem>> _orders = {};

  /// 指定テーブルのアイテム一覧を返す（コピー）。存在しない場合は空リスト。
  List<ScannedItem> getItems(String tableNumber) {
    final items = _orders[tableNumber];
    if (items == null) return [];
    return items.map((e) => e.copy()).toList();
  }

  /// 指定テーブルのアイテムを保存する。空の場合はエントリを削除する。
  void saveItems(String tableNumber, List<ScannedItem> items) {
    if (items.isEmpty) {
      _orders.remove(tableNumber);
    } else {
      _orders[tableNumber] = items.map((e) => e.copy()).toList();
    }
  }

  /// 指定テーブルのデータを削除する（会計完了・全消去時）。
  void clearTable(String tableNumber) {
    _orders.remove(tableNumber);
  }

  /// 注文中（アイテムがある）テーブル番号の一覧を返す。
  List<String> get activeTables => List.unmodifiable(_orders.keys.toList());

  bool hasItems(String tableNumber) {
    final items = _orders[tableNumber];
    return items != null && items.isNotEmpty;
  }
}
