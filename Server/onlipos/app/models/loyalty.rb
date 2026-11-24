# 会計・返品・取消に伴う、会員のポイントと掛売残高の増減
module Loyalty
  module_function

  # 会計: 利用ポイントの消費・掛売の計上・ポイントの付与
  def apply_sale!(sale, payments)
    used = amount_of(payments, "points")
    credit = amount_of(payments, "house_account")
    customer = sale.customer
    raise ArgumentError, "ポイント・掛売の利用には会員の指定が必要です" if customer.nil? && (used + credit).positive?
    return if customer.nil?

    customer.add_points!(-used, kind: :used, sale: sale) if used.positive?
    customer.add_receivable!(credit, sale: sale) if credit.positive?

    earned = earnable_points(sale, used)
    customer.add_points!(earned, kind: :earned, sale: sale)
    sale.update_columns(points_earned: earned)
    Customer.where(id: customer.id).update_all([ "visits_count = visits_count + 1, last_visited_at = ?", sale.sold_at ])
  rescue Customer::InsufficientPoints, Customer::CreditNotAllowed => e
    raise ArgumentError, e.message
  end

  # 返品: 付与ポイントを返金額の割合だけ取り消し、ポイント・掛売で支払われた分を戻す
  def apply_refund!(refund)
    sale = refund.sale
    customer = sale.customer
    return if customer.nil?

    if sale.points_earned.positive? && sale.total_amount.positive?
      refunded_total = sale.refunds.sum(:total_amount)
      target = sale.points_earned * [ refunded_total, sale.total_amount ].min / sale.total_amount
      already = -PointTransaction.where(sale: sale, kind: :reversed).sum(:points)
      customer.add_points!(-(target - already), kind: :reversed, sale: sale, refund: refund, floor: true) if target > already
    end

    returned = refund.refund_payments.points.sum(:amount)
    customer.add_points!(returned, kind: :returned, sale: sale, refund: refund)
    customer.add_receivable!(-refund.refund_payments.house_account.sum(:amount), refund: refund, sale: sale)
  end

  # 取消: すべて元に戻す
  def apply_void!(sale)
    sale.coupon&.release!
    customer = sale.customer
    return if customer.nil?

    customer.add_points!(-sale.points_earned, kind: :reversed, sale: sale, floor: true)
    customer.add_points!(sale.sale_payments.points.sum(:amount), kind: :returned, sale: sale)
    customer.add_receivable!(-sale.sale_payments.house_account.sum(:amount), sale: sale)
  end

  def earnable_points(sale, used)
    unit = sale.user.point_yen_per_point
    unit.positive? ? [ sale.total_amount - used, 0 ].max / unit : 0
  end

  def amount_of(payments, method)
    code = PaymentMethods::VALUES[method.to_sym]
    payments.sum { |p| p[:method].to_i == code ? p[:amount].to_i : 0 }
  end
end
