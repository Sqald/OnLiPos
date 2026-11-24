# 税率の一括変更（例: 飲食料品 8% → 1%）を予約するための計算。
# 内税商品は「税抜額を維持（税込価格を変える）」か「税込価格を維持」かを選べる。
class TaxRateChangePlanner
  Row = Struct.new(:product, :store, :current_price, :new_price, keyword_init: true)

  # keep: "ex_tax"（税抜額を維持） / "in_tax"（税込価格を維持）
  def initialize(account, from_rate:, to_rate:, keep:, excluded_category_ids: [])
    @account = account
    @from_rate = from_rate.to_i
    @to_rate = to_rate.to_i
    @keep = keep
    @excluded = Array(excluded_category_ids).map(&:to_i)
  end

  def products
    scope = @account.products.active.where(tax_rate: @from_rate).where.not(tax_type: :tax_free)
    scope = scope.where("product_category_id IS NULL OR product_category_id NOT IN (?)", @excluded) if @excluded.any?
    scope.order(:code)
  end

  # 商品マスタと店舗価格の変更内容
  def rows
    list = products.to_a
    prices = Price.where(product_id: list.map(&:id)).includes(:store).group_by(&:product_id)
    list.flat_map do |product|
      [ Row.new(product: product, current_price: product.price, new_price: converted(product, product.price)) ] +
        prices.fetch(product.id, []).map { |p| Row.new(product: product, store: p.store, current_price: p.amount, new_price: converted(product, p.amount)) }
    end
  end

  def schedule!(effective_on:, note: nil)
    batch = SecureRandom.hex(8)
    ScheduledProductChange.transaction do
      rows.each do |row|
        changed_price = row.new_price if row.new_price != row.current_price
        next if row.store && changed_price.nil?

        ScheduledProductChange.create!(user: @account, product: row.product, store: row.store, effective_on: effective_on, price: changed_price,
                                       tax_rate: (@to_rate unless row.store), note: note, batch: batch)
      end
    end
    batch
  end

  private

  # 外税商品は税抜価格なので変わらない
  def converted(product, price)
    return price if @keep == "in_tax" || !product.tax_inclusive?

    ex_tax = Rational(price * 100, 100 + @from_rate)
    (ex_tax * (100 + @to_rate) / 100).round
  end
end
