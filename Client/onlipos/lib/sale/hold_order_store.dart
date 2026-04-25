import 'sale_item.dart';

class HoldOrder {
  final int holdNumber;
  final String operatorName;
  final int operatorId;
  final List<ScannedItem> items;
  final DateTime createdAt;
  final int totalAmount;

  const HoldOrder({
    required this.holdNumber,
    required this.operatorName,
    required this.operatorId,
    required this.items,
    required this.createdAt,
    required this.totalAmount,
  });
}

/// 小売店モード用：保留注文をアプリ内メモリで保持するシングルトン。
/// アプリが終了すると消える（永続化なし）。
class HoldOrderStore {
  static final HoldOrderStore _instance = HoldOrderStore._internal();
  factory HoldOrderStore() => _instance;
  HoldOrderStore._internal();

  final Map<int, HoldOrder> _holds = {};
  int _nextHoldNumber = 1;

  /// 新規保留を追加し、割り当てた保留番号を返す。
  int addHold({
    required String operatorName,
    required int operatorId,
    required List<ScannedItem> items,
    required int totalAmount,
  }) {
    final num = _nextHoldNumber++;
    _holds[num] = HoldOrder(
      holdNumber: num,
      operatorName: operatorName,
      operatorId: operatorId,
      items: items.map((e) => e.copy()).toList(),
      createdAt: DateTime.now(),
      totalAmount: totalAmount,
    );
    return num;
  }

  HoldOrder? getHold(int number) => _holds[number];

  /// 保留を取り出し（削除）、アイテムのコピーを返す。存在しない場合は空リスト。
  List<ScannedItem> recallHold(int number) {
    final hold = _holds.remove(number);
    if (hold == null) return [];
    return hold.items.map((e) => e.copy()).toList();
  }

  HoldOrder? recallHoldWithInfo(int number) => _holds.remove(number);

  void removeHold(int number) {
    _holds.remove(number);
  }

  List<HoldOrder> get allHolds {
    final list = _holds.values.toList();
    list.sort((a, b) => a.holdNumber.compareTo(b.holdNumber));
    return list;
  }

  bool get isEmpty => _holds.isEmpty;
}
