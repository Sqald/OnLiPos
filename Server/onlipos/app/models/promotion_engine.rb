# 会計時点で有効な自動値引きの判定と計算。クライアント（lib/sale/promotion.dart）と同じ規則で計算する。
class PromotionEngine
  SetDiscount = Struct.new(:promotion, :lines, :amount, keyword_init: true)

  # 端末の時計のずれ・会計操作中の時間経過に対する許容（この範囲で有効だったものを認める）
  TOLERANCE = 10.minutes

  def initialize(account, at: Time.current)
    @promotions = account.promotions.where(active: true).includes(:products).order(:id).to_a
    @at = at
  end

  def time_sales(product)
    current.select { |p| p.time_sale? && p.targets?(product) }
  end

  def time_sale_prices(product, base_prices)
    time_sales(product).flat_map { |p| base_prices.map { |base| p.sale_price(base) } }.uniq
  end

  # lines: product / quantity / unit_price / eligible を持つ明細の配列。
  # 1つの明細は1つの値引きにだけ使う（登録の古い順）
  def set_discounts(lines)
    remaining = lines.select(&:eligible)
    current.reject(&:time_sale?).filter_map do |promotion|
      targets = remaining.select { |l| promotion.targets?(l.product) }
      amount = promotion.set_discount(targets.flat_map { |l| [ l.unit_price ] * l.quantity })
      next if amount.zero?

      remaining -= targets
      SetDiscount.new(promotion: promotion, lines: targets, amount: amount)
    end
  end

  private

  def current
    @current ||= @promotions.select { |p| [ @at, @at - TOLERANCE, @at + TOLERANCE ].any? { |time| p.active_at?(time) } }
  end
end
