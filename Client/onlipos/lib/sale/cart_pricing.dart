/// カートの金額計算（自動値引き・まとめ買い・小計割引・税）を1か所にまとめる。
/// サーバー（Api::V1::SalesController）が会計時に同じ計算をして照合するため、
/// 割引の按分・税率ごとの端数処理・明細の順序を必ず一致させること。
library;

import 'package:onlipos/product/product.dart';
import 'package:onlipos/sale/promotion.dart';
import 'package:onlipos/sale/sale_item.dart';
import 'package:onlipos/sale/tax_breakdown_calculator.dart';

/// 会計全体への割引（小計割引・クーポン）
class OrderDiscount {
  final String type; // amount / percent
  final int value;
  final String reason;
  final String? couponCode;

  const OrderDiscount({
    required this.type,
    required this.value,
    required this.reason,
    this.couponCode,
  });

  int discountFor(int total) {
    if (type == 'percent') return total * value ~/ 100;
    // クーポンは小計を上限とする。手動の割引は小計を超えるとサーバーが拒否する
    return value > total ? total : value;
  }
}

/// サーバーの明細1行に対応する金額（セット商品は構成商品ごとに1行）
class PricedLine {
  final ScannedItem item;
  final int taxRate;
  final int taxType;
  int amount;

  PricedLine({
    required this.item,
    required this.taxRate,
    required this.taxType,
    required this.amount,
  });
}

class CartQuote {
  /// サーバーへ送る明細
  final List<Map<String, dynamic>> details;

  /// レシートに印字する明細（割引前の金額）
  final List<Map<String, dynamic>> receiptDetails;
  final List<Map<String, int>> taxBreakdown;
  final int itemCount;

  /// 割引前の明細合計
  final int subtotal;
  final int promotionDiscount;
  final List<({String name, int amount})> promotions;
  final int orderDiscount;

  /// 支払合計（税込）
  final int total;
  final int tax;

  /// 手動の価格変更・小計割引があり、値引き権限者の認証が必要か
  final bool needsDiscountApproval;

  /// 年齢確認が必要な最大の年齢（不要なら null）
  final int? requiredAge;

  const CartQuote({
    required this.details,
    required this.receiptDetails,
    required this.taxBreakdown,
    required this.itemCount,
    required this.subtotal,
    required this.promotionDiscount,
    required this.promotions,
    required this.orderDiscount,
    required this.total,
    required this.tax,
    required this.needsDiscountApproval,
    required this.requiredAge,
  });
}

class CartPricing {
  final List<Promotion> promotions;
  final String rounding;

  const CartPricing({this.promotions = const [], this.rounding = 'round_down'});

  CartQuote quote(
    List<ScannedItem> items, {
    OrderDiscount? orderDiscount,
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();
    final active = promotions.where((p) => p.activeAt(now)).toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    for (final item in items) {
      _applyTimeSale(item, active);
    }
    final subtotal = items.fold(0, (s, i) => s + i.subtotal);
    final lines = items.expand(_linesOf).toList();

    // まとめ買い: 1つの明細は1つの値引きにだけ使う（登録の古い順）
    final applied = <({String name, int amount})>[];
    var remaining = items.where(_setEligible).toList();
    for (final promotion in active.where((p) => !p.isTimeSale)) {
      final targets = remaining
          .where((i) => promotion.targets(i.product))
          .toList();
      final units = targets
          .expand((i) => List.filled(i.quantity, i.price))
          .toList();
      final amount = promotion.setDiscount(units);
      if (amount == 0) continue;
      _allocate(lines.where((l) => targets.contains(l.item)).toList(), amount);
      applied.add((name: promotion.name, amount: amount));
      remaining = remaining.where((i) => !targets.contains(i)).toList();
    }
    final promotionDiscount = applied.fold(0, (s, a) => s + a.amount);

    final beforeOrderDiscount = lines.fold(0, (s, l) => s + l.amount);
    final int discount = orderDiscount?.discountFor(beforeOrderDiscount) ?? 0;
    _allocate(lines, discount);

    final breakdown = TaxBreakdownCalculator.fromDetails(
      lines
          .map(
            (l) => {
              'tax_rate': l.taxRate,
              'tax_type': l.taxType,
              'subtotal': l.amount,
            },
          )
          .toList(),
      rounding: rounding,
    );

    return CartQuote(
      details: items.map(_detail).toList(),
      receiptDetails: items.map(_receiptDetail).toList(),
      taxBreakdown: breakdown,
      itemCount: items.fold(0, (s, i) => s + i.quantity),
      subtotal: subtotal,
      promotionDiscount: promotionDiscount,
      promotions: applied,
      orderDiscount: discount,
      total: breakdown.fold(0, (s, b) => s + b['taxable_amount']!),
      tax: breakdown.fold(0, (s, b) => s + b['tax_amount']!),
      needsDiscountApproval:
          items.any((i) => i.overridePrice != null) ||
          (orderDiscount != null && orderDiscount.couponCode == null),
      requiredAge: items.fold<int?>(null, (age, item) {
        final ages = [
          item.product.minAge,
          ...item.components.map((c) => c.minAge),
        ].whereType<int>();
        return ages.fold<int?>(age, (a, b) => a == null || b > a ? b : a);
      }),
    );
  }

  // 有効なタイムセールのうち最も安い価格を設定する（手動の価格変更が優先）
  void _applyTimeSale(ScannedItem item, List<Promotion> active) {
    item.promotionPrice = null;
    item.promotionName = null;
    if (item.isBundle || item.overridePrice != null) return;
    final base = item.product.basePrice(item.eatIn);
    for (final p in active.where(
      (p) => p.isTimeSale && p.targets(item.product),
    )) {
      final price = p.salePrice(base);
      if (price < (item.promotionPrice ?? base)) {
        item.promotionPrice = price;
        item.promotionName = p.name;
      }
    }
  }

  bool _setEligible(ScannedItem item) =>
      !item.isBundle &&
      item.bundleCode == null &&
      item.overridePrice == null &&
      item.promotionPrice == null &&
      item.weightGrams == null;

  // サーバーと同じ単位の行に分ける。セット商品は販売価格を構成商品の定価比で按分し、端数は最後に寄せる
  List<PricedLine> _linesOf(ScannedItem item) {
    if (!item.isBundle) {
      return [
        PricedLine(
          item: item,
          taxRate: item.taxRate,
          taxType: item.product.taxType,
          amount: item.subtotal,
        ),
      ];
    }
    final total = item.subtotal;
    final weights = item.components
        .map((c) => c.weight * item.quantity)
        .toList();
    final sum = weights.fold(0, (s, w) => s + w);
    final List<int> shares = weights
        .map((w) => sum > 0 ? total * w ~/ sum : total ~/ weights.length)
        .toList();
    shares[shares.length - 1] += total - shares.fold<int>(0, (s, a) => s + a);
    return [
      for (var i = 0; i < shares.length; i++)
        PricedLine(
          item: item,
          taxRate: item.components[i].taxRate,
          taxType: TaxType.inclusive,
          amount: shares[i],
        ),
    ];
  }

  // 割引額を明細へ按分する（端数は、負にならない最後の明細に寄せる）
  void _allocate(List<PricedLine> lines, int discount) {
    if (discount <= 0 || lines.isEmpty) return;
    final base = lines.fold(0, (s, l) => s + l.amount);
    if (base <= 0) return;
    final List<int> shares = lines
        .map((l) => discount * l.amount ~/ base)
        .toList();
    final rest = discount - shares.fold<int>(0, (s, a) => s + a);
    for (var i = lines.length - 1; i >= 0; i--) {
      if (lines[i].amount - shares[i] >= rest) {
        shares[i] += rest;
        break;
      }
    }
    for (var i = 0; i < lines.length; i++) {
      lines[i].amount -= shares[i];
    }
  }

  Map<String, dynamic> _detail(ScannedItem item) {
    if (item.isBundle) {
      return {
        'bundle_code': item.bundleCode,
        'product_name': item.bundleName ?? item.product.name,
        'quantity': item.quantity,
        'unit_price': item.price,
        'subtotal': item.subtotal,
      };
    }
    return {
      'product_id': item.product.id,
      'product_name': item.product.name,
      'product_code': item.product.code,
      'quantity': item.quantity,
      'unit_price': item.price,
      'subtotal': item.subtotal,
      'tax_rate': item.taxRate,
      'tax_type': item.product.taxType,
      'tax_amount': item.taxAmount,
      'service_type': item.eatIn ? 'eat_in' : 'takeout',
      if (item.options.isNotEmpty)
        'options': item.options.map((o) => o.id).toList(),
      if (item.price < item.regularPrice)
        'original_unit_price': item.regularPrice,
      if (item.discountReason != null) 'discount_reason': item.discountReason,
      if (item.weightGrams != null) 'weight_grams': item.weightGrams,
    };
  }

  Map<String, dynamic> _receiptDetail(ScannedItem item) => {
    ..._detail(item),
    'product_name': [
      item.bundleName ?? item.product.name,
      if (item.options.isNotEmpty)
        '(${item.options.map((o) => o.name).join('・')})',
      if (item.eatIn) '[店内]',
    ].join(' '),
    'tax_rate': item.isBundle ? item.components.first.taxRate : item.taxRate,
    if (item.promotionName != null) 'discount_reason': item.promotionName,
  };
}
