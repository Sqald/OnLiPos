# レジセッション（開設〜精算の1営業単位 = Zレポートの区切り）。
# 売上・返品・実査・入出金はこのセッションに紐付き、現金照合の基準期間となる。
# 精算（close）時に集計スナップショットを確定保存し、以後は変更しない。
class RegisterSession < ApplicationRecord
  # アソシエーション
  belongs_to :user
  belongs_to :store
  belongs_to :pos_token
  belongs_to :opening_employee, class_name: "Employee", optional: true
  belongs_to :closing_employee, class_name: "Employee", optional: true

  has_many :sales, dependent: :nullify
  has_many :refunds, dependent: :nullify
  has_many :cash_logs, dependent: :nullify
  has_many :cash_movements, dependent: :nullify

  enum :status, { open: 0, closed: 1 }

  # バリデーション
  validates :business_date, presence: true
  validates :z_number, presence: true, numericality: { only_integer: true, greater_than: 0 },
                       uniqueness: { scope: :pos_token_id }
  validates :opened_at, presence: true
  validates :opening_float, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :closed_at, :closing_counted_amount, presence: true, if: :closed?

  # 精算済みセッションのスナップショットは凍結する（改ざん防止）。
  # closed への遷移そのもの（close処理）だけを許可する。
  def readonly?
    persisted? && status_was == "closed"
  end

  # セッション中の集計値（点検 X レポート・精算 Z レポート共用）。
  # 精算時はこの値をスナップショット列に確定保存する。
  def current_totals
    completed_sales = sales.where(status: Sale.statuses[:completed])
    voided_sales    = sales.where(status: Sale.statuses[:voided])

    {
      sales_count:       completed_sales.count,
      sales_total:       completed_sales.sum(:total_amount),
      refund_count:      refunds.count,
      refund_total:      refunds.sum(:total_amount),
      void_count:        voided_sales.count,
      void_total:        voided_sales.sum(:total_amount),
      discount_total:    completed_sales.sum(:total_discount),
      cash_sales_total:  current_cash_sales_total,
      cash_refund_total: allocated_cash_refund_total,
      cash_in_total:     cash_movements.inbound.sum(:amount),
      cash_out_total:    cash_movements.outbound.sum(:amount)
    }
  end

  # 現時点の理論在高。
  # 釣銭準備金 + 現金売上 − 現金返金 + 入金 − 出金 − 旧方式の途中回収
  def expected_cash_now(totals = current_totals)
    opening_float +
      totals[:cash_sales_total] - totals[:cash_refund_total] +
      totals[:cash_in_total] - totals[:cash_out_total] -
      legacy_pickup_total
  end

  # X/Z レポート印字用の内訳（決済手段別・税率別・入出金明細）
  def report_breakdown
    completed = { register_session_id: id, status: Sale.statuses[:completed] }

    payment_breakdown = SalePayment.joins(:sale)
                                   .where(sales: completed)
                                   .group(:method)
                                   .sum(:amount)

    tax_rows = Saledetail.joins(:sale)
                         .where(sales: completed)
                         .group("saledetails.tax_rate")
                         .pluck(Arel.sql("saledetails.tax_rate, SUM(saledetails.subtotal), SUM(saledetails.tax_amount)"))

    refund_tax_rows = RefundDetail.joins(:refund)
                                  .where(refunds: { register_session_id: id })
                                  .group("refund_details.tax_rate")
                                  .pluck(Arel.sql("refund_details.tax_rate, SUM(refund_details.subtotal), SUM(refund_details.tax_amount)"))
    refund_by_rate = refund_tax_rows.to_h { |rate, subtotal, tax| [ rate, [ subtotal.to_i, tax.to_i ] ] }

    tax_breakdown = tax_rows.sort_by(&:first).map do |rate, subtotal, tax|
      refund_subtotal, refund_tax = refund_by_rate[rate] || [ 0, 0 ]
      {
        tax_rate:        rate,
        sales_amount:    subtotal.to_i,
        sales_tax:       tax.to_i,
        refund_amount:   refund_subtotal,
        refund_tax:      refund_tax,
        net_amount:      subtotal.to_i - refund_subtotal,
        net_tax:         tax.to_i - refund_tax
      }
    end

    movements = cash_movements.order(:occurred_at).map do |m|
      { kind: m.kind, direction: m.direction, amount: m.amount, reason: m.reason, occurred_at: m.occurred_at }
    end

    {
      payment_breakdown: payment_breakdown,
      tax_breakdown:     tax_breakdown,
      cash_movements:    movements,
      legacy_pickup_total: legacy_pickup_total
    }
  end

  # 旧方式（cash_logs.is_pickup）の途中回収合計。
  # 新方式は cash_movements(kind: pickup) に記録されるため、二重計上にはならない
  def legacy_pickup_total
    cash_logs.where(is_pickup: true).sum(:pickup_amount).to_i
  end

  private

  # スナップショット列 cash_sales_total とは別名にする（attribute reader を隠さない）
  def current_cash_sales_total
    SalePayment.joins(:sale)
               .where(method: :cash)
               .where(sales: { register_session_id: id, status: Sale.statuses[:completed] })
               .sum(:amount)
  end

  # 返品の現金分。元売上の現金支払い比率で按分する（cash_check_baseline と同式）
  def allocated_cash_refund_total
    Refund.joins(:sale)
          .joins(
            "LEFT JOIN (
              SELECT sale_id, SUM(amount) AS cash_amount
              FROM sale_payments
              WHERE method = 0
              GROUP BY sale_id
            ) AS cash_sums ON cash_sums.sale_id = sales.id"
          )
          .where(refunds: { register_session_id: id })
          .where("sales.total_amount > 0")
          .sum("ROUND(refunds.total_amount::numeric * COALESCE(cash_sums.cash_amount, 0) / sales.total_amount)")
          .to_i
  end
end
