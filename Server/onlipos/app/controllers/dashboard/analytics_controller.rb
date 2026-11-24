require "csv"

# 売上分析画面。いつ・どこで・誰が・何を・いくつ・いくらで・どうやって売れたかを、
# 任意の1軸 / 2軸（クロス集計）でグラフと表にして確認する。集計本体は SalesAnalysis。
class Dashboard::AnalyticsController < Dashboard::BaseController
  DEFAULT_DAYS = 30
  MAX_DAYS = 366 * 3

  # よく使う切り口（ワンクリックで切り替え）
  PRESETS = [
    { label: "日別推移",       row: "day" },
    { label: "店舗別",         row: "store" },
    { label: "従業員別",       row: "employee" },
    { label: "商品別",         row: "product" },
    { label: "カテゴリ別",     row: "category" },
    { label: "時間帯別",       row: "hour" },
    { label: "曜日別",         row: "weekday" },
    { label: "支払方法別",     row: "payment" },
    { label: "店舗×月",        row: "month",    col: "store" },
    { label: "従業員×日",      row: "day",      col: "employee" },
    { label: "商品×店舗",      row: "product",  col: "store" },
    { label: "従業員×商品",    row: "employee", col: "product" },
    { label: "店舗×時間帯",    row: "hour",     col: "store" },
    { label: "カテゴリ×曜日",  row: "weekday",  col: "category" }
  ].freeze

  # 行ラベルをクリックしたとき、その値で絞り込んで次に見る切り口
  DRILL = {
    "store"    => [ :store_id, "employee" ],
    "pos"      => [ :pos_token_id, "employee" ],
    "employee" => [ :employee_id, "product" ],
    "product"  => [ :product_id, "day" ],
    "category" => [ :category_id, "product" ],
    "payment"  => [ :payment_method, "product" ]
  }.freeze

  helper_method :analysis_params, :drill_params

  def index
    @from, @to = date_range
    @stores = current_account.stores.order(:name)
    @pos_tokens = PosToken.joins(:store).where(stores: { user_id: current_account.id }).order("stores.name", :name)
    @employees = current_account.employees.order(:code)
    @categories = ProductCategory.where(user_id: current_account.id).order(:display_order, :name)
    @products = current_account.products.order(:code)

    @analysis = SalesAnalysis.new(
      user: current_account,
      from: @from, to: @to,
      row_dim: params[:row], col_dim: params[:col], metric: params[:metric],
      filters: filter_params,
      include_refunds: params[:refunds] != "0",
      row_limit: params[:limit].presence || 30
    )

    respond_to do |format|
      format.html
      format.csv do
        send_data analysis_csv, type: "text/csv; charset=UTF-8",
                                filename: "sales_analysis_#{@from}_#{@to}.csv"
      end
    end
  end

  private

  # 期間（営業日）。未指定は直近30日、逆転は入れ替え、長すぎる期間は上限で切る
  def date_range
    to = parse_date(params[:to]) || Date.current
    from = parse_date(params[:from]) || (to - (DEFAULT_DAYS - 1))
    from, to = to, from if from > to
    from = to - (MAX_DAYS - 1) if (to - from).to_i >= MAX_DAYS
    [ from, to ]
  end

  def parse_date(value)
    Date.iso8601(value.to_s) if value.present?
  rescue Date::Error
    nil
  end

  def filter_params
    SalesAnalysis::FILTERS.keys.index_with { |k| params[k].presence }.compact
  end

  # 画面内リンク用: 現在の条件に上書きを重ねたパラメータ
  def analysis_params(overrides = {})
    base = {
      from: @from.to_s, to: @to.to_s, row: @analysis.row_dim, col: @analysis.col_dim,
      metric: @analysis.metric, refunds: (@analysis.include_refunds ? nil : "0"), limit: params[:limit].presence
    }.merge(filter_params)
    base.merge(overrides).compact_blank
  end

  # 行のドリルダウン先（なければ nil）
  def drill_params(row_key)
    return nil if row_key == SalesAnalysis::OTHER_KEY
    filter, next_dim = DRILL[@analysis.row_dim]
    return nil unless filter
    analysis_params(filter => row_key, row: next_dim, col: nil)
  end

  def analysis_csv
    a = @analysis
    unit_metric = a.metric_info[:label]
    csv = CSV.generate do |out|
      out << [ "売上分析", "#{@from}〜#{@to}", "指標: #{unit_metric}", (a.include_refunds ? "返品控除後（純売上）" : "返品控除前") ]
      if a.cross?
        out << [ a.row_dimension[:label] ] + a.columns.map(&:last) + [ "合計" ]
        a.rows.each do |row|
          out << [ row.label ] + a.columns.map { |k, _| row.cells[k].value(a.metric) } + [ row.total.value(a.metric) ]
        end
        out << [ "合計" ] + a.columns.map { |k, _| a.column_totals[k].value(a.metric) } + [ a.totals.value(a.metric) ]
      else
        out << [ a.row_dimension[:label], "売上金額", "販売点数", "客数", "客単価", "平均単価", "値引額", "返品額" ]
        (a.rows + [ SalesAnalysis::Row.new(label: "合計", total: a.totals) ]).each do |row|
          t = row.total
          out << [ row.label, t.amount, t.quantity, t.tickets, t.value("avg_ticket"), t.value("avg_price"), t.discount, t.refund_amount ]
        end
      end
    end
    "\xEF\xBB\xBF#{csv}"
  end
end
