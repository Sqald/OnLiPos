/// 自動値引き（サーバーの Promotion / PromotionEngine と同じ規則）。
library;

import 'package:onlipos/product/product.dart';

class Promotion {
  final int id;
  final String name;
  final String kind; // time_sale / set_price / set_percent
  final int? categoryId;
  final List<int> productIds;
  final int? percentOff;
  final int? fixedPrice;
  final int? setQuantity;
  final String? startsOn;
  final String? endsOn;
  final int? startMinute;
  final int? endMinute;
  final List<int> weekdays; // 0 = 日曜

  const Promotion({
    required this.id,
    required this.name,
    required this.kind,
    this.categoryId,
    this.productIds = const [],
    this.percentOff,
    this.fixedPrice,
    this.setQuantity,
    this.startsOn,
    this.endsOn,
    this.startMinute,
    this.endMinute,
    this.weekdays = const [],
  });

  factory Promotion.fromMap(Map<String, dynamic> map) {
    int? number(String key) => (map[key] as num?)?.toInt();
    List<int> numbers(String key) => ((map[key] as List<dynamic>?) ?? [])
        .map((e) => (e as num).toInt())
        .toList();
    return Promotion(
      id: number('id')!,
      name: map['name'] as String,
      kind: map['kind'] as String,
      categoryId: number('category_id'),
      productIds: numbers('product_ids'),
      percentOff: number('percent_off'),
      fixedPrice: number('fixed_price'),
      setQuantity: number('set_quantity'),
      startsOn: map['starts_on'] as String?,
      endsOn: map['ends_on'] as String?,
      startMinute: number('start_minute'),
      endMinute: number('end_minute'),
      weekdays: numbers('weekdays'),
    );
  }

  bool get isTimeSale => kind == 'time_sale';

  bool activeAt(DateTime time) {
    final date = time.toIso8601String().substring(0, 10);
    final minute = time.hour * 60 + time.minute;
    return (startsOn == null || date.compareTo(startsOn!) >= 0) &&
        (endsOn == null || date.compareTo(endsOn!) <= 0) &&
        (weekdays.isEmpty || weekdays.contains(time.weekday % 7)) &&
        (startMinute == null || minute >= startMinute!) &&
        (endMinute == null || minute < endMinute!);
  }

  bool targets(Product product) =>
      (categoryId != null && product.categoryId == categoryId) ||
      productIds.contains(product.id);

  /// タイムセールの販売単価（通常単価より高くはしない）
  int salePrice(int base) {
    final price = fixedPrice ?? base * (100 - percentOff!) ~/ 100;
    return price < base ? price : base;
  }

  /// まとめ買いの割引額。[units] は対象の単価（1点ずつ）
  int setDiscount(List<int> units) {
    final size = setQuantity!;
    if (units.length < size) return 0;
    final sorted = [...units]..sort((a, b) => b.compareTo(a));
    if (kind == 'set_percent') {
      return sorted.fold(0, (s, u) => s + u) * percentOff! ~/ 100;
    }
    final count = units.length ~/ size * size;
    final discount =
        sorted.take(count).fold(0, (s, u) => s + u) -
        count ~/ size * fixedPrice!;
    return discount > 0 ? discount : 0;
  }
}
