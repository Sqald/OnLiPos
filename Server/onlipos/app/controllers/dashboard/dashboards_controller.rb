# ダッシュボードのトップページ（ホーム画面）を担当するコントローラ。
# 今日の売上・やること・はじめの準備の進み具合をまとめて表示する。
class Dashboard::DashboardsController < Dashboard::BaseController
  Todo = Struct.new(:title, :detail, :path, :info, keyword_init: true)
  Step = Struct.new(:title, :detail, :path, :done, keyword_init: true)

  def index
    @stores = current_account.stores.includes(:pos_tokens).order(:name)
    @pos_tokens = @stores.flat_map(&:pos_tokens)
    load_sales_summary
    @todos = todos
    @steps = setup_steps
  end

  private

  def load_sales_summary
    today = Date.current
    sales = Sale.where(user_id: current_account.id, status: :completed)
    @today_total, @today_count = sales.where(business_date: today).pick(Arel.sql("COALESCE(SUM(total_amount), 0)"), Arel.sql("COUNT(*)"))
    @yesterday_total = sales.where(business_date: today - 1).sum(:total_amount)
    @today_refund = Refund.where(user_id: current_account.id, business_date: today).sum(:total_amount)
    @month_total = sales.where(business_date: today.beginning_of_month..today).sum(:total_amount)
    by_day = sales.where(business_date: (today - 6)..today).group(:business_date).sum(:total_amount)
    @week = ((today - 6)..today).map { |d| [ d, by_day[d].to_i ] }
  end

  # いま対応が必要なことと、知っておくとよいこと
  def todos
    reviews = Sale.where(user: current_account).needing_review.count
    low = low_stock_count
    expired = @pos_tokens.count { |p| !%i[authenticated disabled pending].include?(p.password_status) }
    diffs = RegisterSession.where(user_id: current_account.id, status: :closed, business_date: 7.days.ago.to_date..).where.not(cash_diff_amount: [ 0, nil ]).count
    upcoming = ScheduledProductChange.where(user_id: current_account.id, applied_at: nil).minimum(:effective_on)
    codes = current_user.recovery_codes_remaining

    [
      (Todo.new(title: "確認が必要な会計が#{reviews}件あります", detail: "オフライン中の価格変更など", path: dashboard_sale_reviews_path) if reviews.positive?),
      (Todo.new(title: "在庫が少ない商品が#{low}件あります", detail: "発注が必要か確認しましょう", path: dashboard_low_stocks_path) if low.positive?),
      (Todo.new(title: "レジの過不足が#{diffs}件あります（過去7日）", detail: "精算時の現金が理論在高と合っていません", path: dashboard_register_sessions_path(diff_only: 1, from: 7.days.ago.to_date, to: Date.current)) if diffs.positive?),
      (Todo.new(title: "パスワードの期限が切れたPOS端末が#{expired}台あります", detail: "再設定すると使えるようになります", path: dashboard_pos_devices_path) if expired.positive?),
      (Todo.new(title: "リカバリーコードの残りが#{codes}個です", detail: "再発行しておくと、端末を紛失しても安心です", path: dashboard_security_path) if codes <= 3),
      (Todo.new(title: "#{I18n.l(upcoming, format: :long)} に価格・税率が変わります", detail: "予約の内容を確認できます", path: dashboard_scheduled_changes_path, info: true) if upcoming)
    ].compact
  end

  def low_stock_count
    StoreStock.joins(:product, :store).where(stores: { user_id: current_account.id })
              .where("products.low_stock_threshold IS NOT NULL AND store_stocks.quantity <= products.low_stock_threshold AND products.status = 0").count
  end

  # 使い始めるまでの手順。すべて終わったら表示しない
  def setup_steps
    steps = [
      Step.new(title: "店舗を登録する", detail: "店名・住所・電話番号（レシートに印字されます）", path: new_dashboard_store_path, done: @stores.any?),
      Step.new(title: "商品を登録する", detail: "1件ずつ、またはCSVでまとめて登録できます", path: new_dashboard_product_path, done: current_account.products.exists?),
      Step.new(title: "従業員を登録する", detail: "レジを操作する人の番号・PIN・権限を決めます", path: new_dashboard_employee_path, done: current_account.employees.exists?),
      Step.new(title: "POS端末を登録する", detail: "レジとして使うタブレットやPCのIDを発行します", path: new_dashboard_pos_device_path, done: @pos_tokens.any?),
      Step.new(title: "端末アプリでログインする", detail: "企業ID・店舗ID・端末ID・パスワードを入力します", path: dashboard_help_path(anchor: "terminal"), done: @pos_tokens.any? { |p| p.last_used_at })
    ]
    steps.all?(&:done) ? [] : steps
  end
end
