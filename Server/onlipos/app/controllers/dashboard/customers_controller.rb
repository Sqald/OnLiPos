# 会員（ポイント・掛売）
class Dashboard::CustomersController < Dashboard::ResourceController
  manages Customer, title: "会員", order: { id: :desc }, search: "会員番号・名前・電話番号",
    columns: { "会員番号" => ->(r, v) { v.link_to(r.code, v.dashboard_customer_path(r)) }, "名前" => :name, "電話" => :phone, "ポイント" => :points,
               "掛売残高" => ->(r, v) { v.yen(r.receivable) }, "来店" => :visits_count, "最終来店" => ->(r, v) { v.datetime(r.last_visited_at) } },
    fields: [ field(:code, "会員番号（空欄で自動採番）", maxlength: 32), field(:name, "名前"), field(:phone, "電話番号"), field(:email, "メールアドレス"),
              field(:birthday, "誕生日", :date), field(:note, "メモ", :textarea, rows: 3), field(:credit_allowed, "掛売を許可する", :checkbox) ]

  def show
    @customer = scope.find(params[:id])
    @point_transactions = @customer.point_transactions.order(id: :desc).limit(50)
    @receivables = @customer.receivable_transactions.order(id: :desc).limit(50)
    @sales = @customer.sales.includes(:store).order(sold_at: :desc).limit(50)
    AuditLog.record("view", target: @customer)
  end

  # ポイントの手動調整・掛売の入金
  def adjust
    customer = scope.find(params[:id])
    amount = params[:amount].to_i
    note = params[:note].to_s.strip.presence
    return redirect_to(dashboard_customer_path(customer), alert: "数量と理由を入力してください。", status: :see_other) if amount.zero? || note.nil?

    if params[:target] == "receivable"
      customer.add_receivable!(-amount.abs, note: "入金: #{note}")
    else
      customer.add_points!(amount, kind: :adjusted, note: note)
    end
    AuditLog.record("update", target: customer, details: { "対象" => params[:target] == "receivable" ? "掛売の入金" : "ポイント調整", "数量" => amount, "理由" => note })
    redirect_to dashboard_customer_path(customer), notice: "登録しました。", status: :see_other
  rescue Customer::InsufficientPoints, Customer::CreditNotAllowed => e
    redirect_to dashboard_customer_path(customer), alert: e.message, status: :see_other
  end

  # 個人情報の削除請求への対応
  def anonymize
    customer = scope.find(params[:id])
    customer.anonymize!
    redirect_to dashboard_customer_path(customer), notice: "個人情報を削除しました（取引記録は残ります）。", status: :see_other
  end

  private

  def filtered_scope = scope.search(params[:q])
end
