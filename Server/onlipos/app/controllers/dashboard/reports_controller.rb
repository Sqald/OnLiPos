require "csv"

class Dashboard::ReportsController < Dashboard::BaseController
  helper_method :search_performed?

  def index
    @stores = current_user.stores.order(:name)
    @allowed_store_ids = @stores.pluck(:id)

    unless search_performed?
      @daily_summary = []
      @monthly_summary = []
      @product_ranking = []
      @payment_summary = []
      @employee_summary = []
      @tax_summary = []
      @total_sales_amount = 0
      @total_sales_count = 0
      @total_discount = 0
      @refund_count = 0
      @refund_total = 0
      @void_count = 0
      @void_total = 0
      return
    end

    # 集計は営業日（business_date）基準・取消（VOID）除外
    scope = build_scope

    @total_sales_amount = scope.sum(:total_amount)
    @total_sales_count  = scope.count

    @daily_summary = scope
      .group(:business_date)
      .order(:business_date)
      .pluck(
        Arel.sql("business_date AS day"),
        Arel.sql("COUNT(*) AS cnt"),
        Arel.sql("SUM(total_amount) AS amount")
      )
      .map { |day, cnt, amount| { day: day, count: cnt, amount: amount } }

    @monthly_summary = scope
      .group("TO_CHAR(business_date, 'YYYY-MM')")
      .order(Arel.sql("TO_CHAR(business_date, 'YYYY-MM') ASC"))
      .pluck(
        Arel.sql("TO_CHAR(business_date, 'YYYY-MM') AS month"),
        Arel.sql("COUNT(*) AS cnt"),
        Arel.sql("SUM(total_amount) AS amount")
      )
      .map { |month, cnt, amount| { month: month, count: cnt, amount: amount } }

    sale_ids = scope.pluck(:id)
    @product_ranking = Saledetail
      .where(sale_id: sale_ids)
      .group(:product_name)
      .order(Arel.sql("SUM(subtotal) DESC"))
      .limit(20)
      .pluck(
        Arel.sql("product_name"),
        Arel.sql("SUM(quantity) AS total_qty"),
        Arel.sql("SUM(subtotal) AS total_amount")
      )
      .map { |name, qty, amount| { name: name, quantity: qty, amount: amount } }

    # 支払い方法別集計（現金/カード/バーコード）
    payment_method_labels = {
      0 => "現金", 1 => "カード", 2 => "バーコード決済", 3 => "電子マネー",
      "cash" => "現金", "card" => "カード", "barcode" => "バーコード決済", "emoney" => "電子マネー"
    }
    @payment_summary = SalePayment
      .where(sale_id: sale_ids)
      .group(:method)
      .order(:method)
      .pluck(
        Arel.sql("method"),
        Arel.sql("COUNT(DISTINCT sale_id) AS cnt"),
        Arel.sql("SUM(amount) AS total")
      )
      .map { |method_int, cnt, total| { label: payment_method_labels[method_int] || method_int.to_s, count: cnt, amount: total } }

    # 割引合計
    @total_discount = scope.sum(:total_discount)

    # 税率別売上（インボイス確定値ベース。返品分を控除）
    refunds_scope = build_refunds_scope
    @refund_count = refunds_scope.count
    @refund_total = refunds_scope.sum(:total_amount)
    @tax_summary = TaxSummary.build(scope, refunds_scope).map do |row|
      {
        tax_rate: row.tax_rate,
        sales_amount: row.sales_amount, sales_tax: row.sales_tax,
        refund_amount: row.refund_amount, refund_tax: row.refund_tax,
        net_amount: row.net_amount, net_tax: row.net_tax
      }
    end

    # 取消（VOID）は売上から除外した上で件数・金額を別掲する
    void_scope = build_scope(status: :voided)
    @void_count = void_scope.count
    @void_total = void_scope.sum(:total_amount)

    # 担当者別売上（sales に employee_id がある場合）
    @employee_summary = scope
      .joins("LEFT JOIN employees ON employees.id = sales.employee_id")
      .group("employees.id", "employees.name", "employees.code")
      .order(Arel.sql("SUM(sales.total_amount) DESC"))
      .pluck(
        Arel.sql("COALESCE(employees.name, '不明') AS emp_name"),
        Arel.sql("COALESCE(employees.code, '-') AS emp_code"),
        Arel.sql("COUNT(sales.id) AS cnt"),
        Arel.sql("SUM(sales.total_amount) AS amount")
      )
      .map { |name, code, cnt, amount| { name: name, code: code, count: cnt, amount: amount } }

    respond_to do |format|
      format.html
      format.csv do
        send_data generate_report_csv,
                  filename: "report_#{Date.current}.csv",
                  type: "text/csv; charset=UTF-8"
      end
    end
  end

  private

  def build_scope(status: :completed)
    scope = Sale.where(user_id: current_user.id, status: Sale.statuses[status])

    if params[:store_id].present? && @allowed_store_ids.include?(params[:store_id].to_i)
      scope = scope.where(store_id: params[:store_id])
    end

    from_date = parse_date(params[:from])&.to_date
    to_date   = parse_date(params[:to])&.to_date

    scope = scope.where(business_date: from_date..) if from_date
    scope = scope.where(business_date: ..to_date) if to_date
    scope
  end

  def build_refunds_scope
    scope = Refund.where(user_id: current_user.id)

    if params[:store_id].present? && @allowed_store_ids.include?(params[:store_id].to_i)
      scope = scope.where(store_id: params[:store_id])
    end

    from_date = parse_date(params[:from])&.to_date
    to_date   = parse_date(params[:to])&.to_date

    scope = scope.where(business_date: from_date..) if from_date
    scope = scope.where(business_date: ..to_date) if to_date
    scope
  end

  def generate_report_csv
    csv = CSV.generate(encoding: "UTF-8") do |csv|
      csv << [ "--- 日次売上 ---" ]
      csv << [ "日付", "件数", "売上金額" ]
      @daily_summary.each { |r| csv << [ r[:day], r[:count], r[:amount] ] }

      csv << []
      csv << [ "--- 月次売上 ---" ]
      csv << [ "年月", "件数", "売上金額" ]
      @monthly_summary.each { |r| csv << [ r[:month], r[:count], r[:amount] ] }

      csv << []
      csv << [ "--- 支払い方法別集計 ---" ]
      csv << [ "支払い方法", "件数", "金額" ]
      @payment_summary.each { |r| csv << [ r[:label], r[:count], r[:amount] ] }

      csv << []
      csv << [ "--- 税率別売上 ---" ]
      csv << [ "税率(%)", "売上(税込)", "うち消費税", "返品(税込)", "うち消費税", "純売上(税込)", "純消費税" ]
      @tax_summary.each do |r|
        csv << [ r[:tax_rate], r[:sales_amount], r[:sales_tax], r[:refund_amount], r[:refund_tax], r[:net_amount], r[:net_tax] ]
      end

      csv << []
      csv << [ "--- 返品・取消 ---" ]
      csv << [ "区分", "件数", "金額" ]
      csv << [ "返品", @refund_count, @refund_total ]
      csv << [ "取消(VOID)", @void_count, @void_total ]

      csv << []
      csv << [ "--- 担当者別売上 ---" ]
      csv << [ "コード", "担当者名", "件数", "売上金額" ]
      @employee_summary.each { |r| csv << [ r[:code], r[:name], r[:count], r[:amount] ] }

      csv << []
      csv << [ "--- 商品別売上ランキング ---" ]
      csv << [ "順位", "商品名", "販売数", "売上金額" ]
      @product_ranking.each_with_index { |r, i| csv << [ i + 1, r[:name], r[:quantity], r[:amount] ] }
    end
    "\xEF\xBB\xBF#{csv}"
  end

  def search_performed?
    params[:store_id].present? || params[:from].present? || params[:to].present?
  end

  def parse_date(str)
    return nil if str.blank?
    Time.zone.parse(str)
  rescue ArgumentError
    nil
  end
end
