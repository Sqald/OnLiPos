# 会計明細の価格・税率がマスタに照らして正しいかを判定する。
#
# 端末から送られた単価はそのまま信用せず、次のいずれかに一致するものだけを「通常価格」とみなす。
#   - 現在の店舗価格 / 定価（店内飲食では店内価格）
#   - 直近（オフライン会計では販売時点以降）に変更される前の価格
#   - 有効なタイムセールの価格
#   - 上記に、選択されたオプションの料金を加えた額
# 一致しない単価は値引き（価格変更）として扱い、discount 権限を持つ担当者の承認を必要とする。
class SalePricePolicy
  # 端末のマスタ同期が遅れることを考慮した猶予（価格のみ。税率は販売日時点のものに限る）
  GRACE = 24.hours

  def initialize(store:, sold_at: Time.current)
    @store = store
    @sold_at = sold_at
    @since = [ sold_at, GRACE.ago ].min
    @promotions = PromotionEngine.new(store.user, at: sold_at)
  end

  attr_reader :promotions

  # 通常価格として認める単価の一覧（オプション料金を含まない）
  def regular_prices(product, eat_in: false)
    prices = [ base_price(product, eat_in: eat_in), store_price(product), product.price ]
    prices.concat(histories(product).flat_map { |h| [ h.price, (h.eat_in_price if eat_in) ] })
    prices.compact.uniq
  end

  # 値引き額の計算の基準になる現在の価格
  def base_price(product, eat_in: false)
    (eat_in && product.eat_in_price) || store_price(product)
  end

  # 単価の判定結果。:regular（通常）/ Promotion（タイムセール）/ nil（価格変更）
  def classify(product, unit_price, eat_in: false, options_price: 0)
    bases = regular_prices(product, eat_in: eat_in)
    return :regular if bases.include?(unit_price - options_price)

    @promotions.time_sales(product).find { |p| bases.any? { |base| p.sale_price(base) == unit_price - options_price } }
  end

  # 認める税率。販売時点で有効だった税率だけを認める（税率変更の前後で取り違えない）
  def tax_rate?(product, tax_rate, eat_in: false)
    tax_rates(product, eat_in: eat_in).include?(tax_rate)
  end

  def tax_rates(product, eat_in: false)
    replaced_after_sale = histories(product).select { |h| h.store_id.nil? && h.tax_rate && h.replaced_at > @sold_at }.min_by(&:replaced_at)
    [ replaced_after_sale ? replaced_after_sale.tax_rate_for(eat_in) : product.tax_rate_for(eat_in) ]
  end

  # 明細の小計の正しい値。量り売りは100gあたりの単価から計算する
  def self.expected_subtotal(unit_price:, quantity:, weight_grams: nil)
    return Rational(unit_price * weight_grams, 100).round if weight_grams

    unit_price * quantity
  end

  private

  def store_price(product)
    @store_prices ||= {}
    @store_prices.fetch(product.id) do
      @store_prices[product.id] = Price.find_by(store_id: @store.id, product_id: product.id)&.amount || product.price
    end
  end

  def histories(product)
    @histories ||= {}
    @histories[product.id] ||= ProductPriceHistory
      .where(product_id: product.id, store_id: [ nil, @store.id ])
      .where("replaced_at > ?", @since).to_a
  end
end
