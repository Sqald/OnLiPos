# 税率別売上集計（申告資料の基礎）。
# 売上は sale_tax_breakdowns、返品は refund_tax_breakdowns の確定値を集計し、
# 内訳を持たないレガシー行は明細（saledetails / refund_details）の積み上げにフォールバックする。
class TaxSummary
  Row = Struct.new(:tax_rate, :sales_amount, :sales_tax, :refund_amount, :refund_tax,
                   :net_amount, :net_tax, keyword_init: true)

  # 売上・返品それぞれの税率別内訳を集計し、両者をマージした Row の配列を返す
  # sales_scope: 集計対象の Sale リレーション（status 等はフィルタ済みであること）
  # refunds_scope: 控除する Refund リレーション
  def self.build(sales_scope, refunds_scope)
    sales = aggregate(
      SaleTaxBreakdown.where(sale_id: sales_scope.select(:id)),
      :taxable_amount, :tax_amount
    )
    merge!(sales, aggregate(
      Saledetail.where(sale_id: sales_scope.where.missing(:sale_tax_breakdowns).select(:id)),
      :subtotal, :tax_amount
    ))

    refunds = aggregate(
      RefundTaxBreakdown.where(refund_id: refunds_scope.select(:id)),
      :taxable_amount, :tax_amount
    )
    merge!(refunds, aggregate(
      RefundDetail.where(refund_id: refunds_scope.where.missing(:refund_tax_breakdowns).select(:id)),
      :subtotal, :tax_amount
    ))

    (sales.keys | refunds.keys).sort.map do |rate|
      sales_amount, sales_tax = sales[rate] || [ 0, 0 ]
      refund_amount, refund_tax = refunds[rate] || [ 0, 0 ]
      Row.new(
        tax_rate: rate,
        sales_amount: sales_amount, sales_tax: sales_tax,
        refund_amount: refund_amount, refund_tax: refund_tax,
        net_amount: sales_amount - refund_amount,
        net_tax: sales_tax - refund_tax
      )
    end
  end

  # tax_rate => [金額合計, 税額合計] のハッシュを作る
  def self.aggregate(scope, amount_column, tax_column)
    scope.group(:tax_rate)
         .pluck(Arel.sql("tax_rate, SUM(#{amount_column}), SUM(#{tax_column})"))
         .to_h { |rate, amount, tax| [ rate, [ amount.to_i, tax.to_i ] ] }
  end
  private_class_method :aggregate

  def self.merge!(base, other)
    other.each do |rate, (amount, tax)|
      current = base[rate] || [ 0, 0 ]
      base[rate] = [ current[0] + amount, current[1] + tax ]
    end
    base
  end
  private_class_method :merge!
end
