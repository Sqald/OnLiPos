# レジ精算（Z）の一覧・詳細
class Dashboard::RegisterSessionsController < Dashboard::BaseController
  def index
    @stores = current_account.stores.order(:name)
    scope = RegisterSession.where(user: current_account).includes(:store, :pos_token, :closing_employee)
    scope = scope.where(store_id: params[:store_id]) if params[:store_id].present?
    scope = scope.where(business_date: parse_date(params[:from])..) if parse_date(params[:from])
    scope = scope.where(business_date: ..parse_date(params[:to])) if parse_date(params[:to])
    scope = scope.where.not(cash_diff_amount: [ nil, 0 ]) if params[:diff_only] == "1"
    scope = scope.order(business_date: :desc, opened_at: :desc)

    respond_to do |format|
      format.html { @sessions = scope.page(params[:page]).per(50) }
      format.csv { send_data sessions_csv(scope), filename: "register_sessions_#{Date.current}.csv", type: "text/csv; charset=UTF-8" }
    end
  end

  def show
    @session = RegisterSession.where(user: current_account).find(params[:id])
    @totals = @session.closed? ? @session.attributes.symbolize_keys : @session.current_totals
    @breakdown = (@session.closed? ? @session.closing_summary : @session.report_breakdown).deep_stringify_keys
    @cash_logs = @session.cash_logs.includes(:employee).order(:created_at)
    @late_sales = @session.closed? ? @session.sales.where("sales.created_at > ?", @session.closed_at).order(:sold_at) : Sale.none
  end

  private

  def sessions_csv(scope)
    headers = %w[営業日 店舗 端末 Z番号 状態 開設 精算 売上件数 売上合計 返品合計 取消合計 割引合計 現金売上 現金返金 入金 出金 理論在高 実査額 過不足 精算担当者]
    CsvExport.generate(headers) do |csv|
      scope.find_each do |s|
        csv << [ s.business_date, s.store.name, s.pos_token.name, s.z_number, s.closed? ? "精算済み" : "営業中", s.opened_at, s.closed_at,
                 s.sales_count, s.sales_total, s.refund_total, s.void_total, s.discount_total, s.cash_sales_total, s.cash_refund_total,
                 s.cash_in_total, s.cash_out_total, s.expected_cash_amount, s.closing_counted_amount, s.cash_diff_amount, s.closing_employee&.name ]
      end
    end
  end
end
