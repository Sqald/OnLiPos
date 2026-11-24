# 返品1件分の返金額を計算する。
# 返金額は「実際に支払われた額（明細の小計）」を基準にし、明細・会計ごとの返金済み額を超えない。
#   - 単価 × 数量では計算しない（量り売り・按分割引・端数のある明細で支払額と食い違うため）
#   - 残数をすべて返品するときは残額をそのまま返すので、分割して返品しても合計が支払額と一致する
class RefundCalculator
  class Error < StandardError; end

  Line = Struct.new(:saledetail, :quantity, :unit_price, :subtotal, :tax_amount, keyword_init: true)
  Result = Struct.new(:lines, :breakdowns, :total_amount, keyword_init: true)

  def initialize(sale)
    @sale = sale
    @tax = TaxCalculator.new(sale.user.tax_rounding_method)
    rows = RefundDetail.joins(:refund).where(refunds: { sale_id: sale.id })
    @refunded_quantities = rows.group(:saledetail_id).sum(:quantity)
    @refunded_subtotals = rows.group(:saledetail_id).sum(:subtotal)
  end

  attr_reader :refunded_quantities

  def remaining_quantity(detail)
    detail.quantity - @refunded_quantities.fetch(detail.id, 0)
  end

  # quantity 個を返品したときの返金額（税計算前の明細額）
  def line_amount(detail, quantity)
    remaining_amount = [ detail.subtotal - @refunded_subtotals.fetch(detail.id, 0), 0 ].max
    return remaining_amount if quantity >= remaining_quantity(detail)

    [ detail.subtotal * quantity / detail.quantity, remaining_amount ].min
  end

  # items: [[Saledetail, 数量], ...]
  def calculate(items)
    # 同じ明細が複数行に分かれていても、残数の判定をすり抜けないようにまとめる
    items = items.group_by(&:first).map { |detail, rows| [ detail, rows.sum(&:last) ] }

    lines = items.map do |detail, quantity|
      remaining = remaining_quantity(detail)
      if quantity > remaining
        raise Error, "返品数量が返品可能数量(#{remaining})を超えています: #{detail.product_name}"
      end

      subtotal = line_amount(detail, quantity)
      Line.new(saledetail: detail, quantity: quantity, unit_price: subtotal / quantity, subtotal: subtotal,
               tax_amount: @tax.line_tax(subtotal, detail.tax_rate, detail.tax_type))
    end

    breakdowns = @tax.breakdowns(lines.map { |l|
      { amount: l.subtotal, tax_rate: l.saledetail.tax_rate, tax_type: l.saledetail.tax_type }
    })
    fit_to_sale_total(breakdowns, completes_sale?(items))
    Result.new(lines: lines, breakdowns: breakdowns, total_amount: breakdowns.sum(&:taxable_amount))
  end

  private

  # この返品で会計の全数量が返品済みになるか
  def completes_sale?(items)
    returning = items.to_h { |detail, quantity| [ detail.id, quantity ] }
    @sale.saledetails.all? { |d| remaining_quantity(d) - returning.fetch(d.id, 0) <= 0 }
  end

  # 外税を分割返品すると税の端数で会計合計とずれるため、会計合計を超えないように（全数返品なら一致するように）
  # 最後の内訳の税額で調整する。端数では説明できない差は異常なデータとして拒否する
  def fit_to_sale_total(breakdowns, completes)
    return if breakdowns.empty?

    refunded = @sale.refunds.sum(:total_amount)
    diff = @sale.total_amount - refunded - breakdowns.sum(&:taxable_amount)
    return if diff.zero? || (diff.positive? && !completes)

    limit = breakdowns.size * (@sale.refunds.size + 1)
    target = breakdowns.reverse.find { |b| b.tax_type.to_s == "exclusive" && b.tax_amount + diff >= 0 }
    if target && diff.abs <= limit
      target.tax_amount += diff
      target.taxable_amount += diff
    elsif diff.negative?
      raise Error, "返金額が会計の残額を超えています"
    end
  end
end
