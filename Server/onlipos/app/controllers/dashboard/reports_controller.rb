require 'csv'

class Dashboard::ReportsController < Dashboard::BaseController
  helper_method :search_performed?

  def index
    @stores = current_user.stores.order(:name)
    @allowed_store_ids = @stores.pluck(:id)

    unless search_performed?
      @daily_summary = []
      @monthly_summary = []
      @product_ranking = []
      @total_sales_amount = 0
      @total_sales_count = 0
      return
    end

    scope = build_scope

    @total_sales_amount = scope.sum(:total_amount)
    @total_sales_count  = scope.count

    @daily_summary = scope
      .group("DATE(sales.created_at AT TIME ZONE 'Asia/Tokyo')")
      .order("DATE(sales.created_at AT TIME ZONE 'Asia/Tokyo') ASC")
      .pluck(
        Arel.sql("DATE(sales.created_at AT TIME ZONE 'Asia/Tokyo') AS day"),
        Arel.sql("COUNT(*) AS cnt"),
        Arel.sql("SUM(total_amount) AS amount")
      )
      .map { |day, cnt, amount| { day: day, count: cnt, amount: amount } }

    @monthly_summary = scope
      .group("TO_CHAR(sales.created_at AT TIME ZONE 'Asia/Tokyo', 'YYYY-MM')")
      .order("TO_CHAR(sales.created_at AT TIME ZONE 'Asia/Tokyo', 'YYYY-MM') ASC")
      .pluck(
        Arel.sql("TO_CHAR(sales.created_at AT TIME ZONE 'Asia/Tokyo', 'YYYY-MM') AS month"),
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

    respond_to do |format|
      format.html
      format.csv do
        send_data generate_report_csv,
                  filename: "report_#{Date.current}.csv",
                  type: 'text/csv; charset=UTF-8'
      end
    end
  end

  private

  def build_scope
    scope = Sale.where(user_id: current_user.id)

    if params[:store_id].present? && @allowed_store_ids.include?(params[:store_id].to_i)
      scope = scope.where(store_id: params[:store_id])
    end

    from_time = parse_date(params[:from])
    to_time   = parse_date(params[:to])&.end_of_day

    scope = scope.where("sales.created_at >= ?", from_time) if from_time
    scope = scope.where("sales.created_at <= ?", to_time) if to_time
    scope
  end

  def generate_report_csv
    csv = CSV.generate(encoding: 'UTF-8') do |csv|
      csv << ['--- 日次売上 ---']
      csv << ['日付', '件数', '売上金額']
      @daily_summary.each { |r| csv << [r[:day], r[:count], r[:amount]] }

      csv << []
      csv << ['--- 月次売上 ---']
      csv << ['年月', '件数', '売上金額']
      @monthly_summary.each { |r| csv << [r[:month], r[:count], r[:amount]] }

      csv << []
      csv << ['--- 商品別売上ランキング ---']
      csv << ['順位', '商品名', '販売数', '売上金額']
      @product_ranking.each_with_index { |r, i| csv << [i + 1, r[:name], r[:quantity], r[:amount]] }
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
