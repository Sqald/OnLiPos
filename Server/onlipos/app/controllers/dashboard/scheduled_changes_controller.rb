# 価格・税率の予約変更と、税率の一括変更
class Dashboard::ScheduledChangesController < Dashboard::BaseController
  def index
    scope = current_account.scheduled_product_changes.includes(:product, :store)
    @changes = (params[:applied] ? scope.where.not(applied_at: nil).order(applied_at: :desc) : scope.pending.order(:effective_on, :id)).page(params[:page]).per(100)
  end

  def create
    product = current_account.products.find_by(code: params.dig(:change, :code).to_s.strip)
    return redirect_to(dashboard_scheduled_changes_path, alert: "商品コードが見つかりません。", status: :see_other) unless product

    change = current_account.scheduled_product_changes.build(change_params.merge(product: product))
    change.store = current_account.stores.find_by(id: params.dig(:change, :store_id))
    if change.effective_on && change.effective_on <= Date.current
      return redirect_to(dashboard_scheduled_changes_path, alert: "適用日は明日以降を指定してください。", status: :see_other)
    end

    if change.save
      AuditLog.record("create", target: product, details: { "予約変更" => change.changes_summary, "適用日" => change.effective_on })
      redirect_to dashboard_scheduled_changes_path, notice: "予約しました。端末には次回の同期で配布されます。", status: :see_other
    else
      redirect_to dashboard_scheduled_changes_path, alert: change.errors.full_messages.join("、"), status: :see_other
    end
  end

  def destroy
    current_account.scheduled_product_changes.pending.find(params[:id]).destroy!
    redirect_to dashboard_scheduled_changes_path, notice: "予約を取り消しました。", status: :see_other
  end

  # 一括予約をまとめて取り消す
  def destroy_batch
    count = current_account.scheduled_product_changes.pending.where(batch: params[:batch].presence || "-").delete_all
    AuditLog.record("destroy", details: { "操作" => "一括予約の取消", "件数" => count })
    redirect_to dashboard_scheduled_changes_path, notice: "#{count}件の予約を取り消しました。", status: :see_other
  end

  # 税率の一括変更: 条件の入力と内容の確認
  def tax_change
    @categories = current_account.product_categories.order(:display_order, :name)
    return unless params[:effective_on].present?

    @planner = planner
    @rows = @planner.rows
  end

  def apply_tax_change
    date = parse_date(params[:effective_on])
    if date.nil? || date <= Date.current
      return redirect_to(tax_change_dashboard_scheduled_changes_path, alert: "適用日は明日以降を指定してください。", status: :see_other)
    end

    count = planner.rows.size
    planner.schedule!(effective_on: date, note: "税率 #{params[:from_rate].to_i}% → #{params[:to_rate].to_i}%")
    AuditLog.record("create", details: { "操作" => "税率の一括変更を予約", "変更" => "#{params[:from_rate].to_i}% → #{params[:to_rate].to_i}%", "適用日" => date, "件数" => count })
    redirect_to dashboard_scheduled_changes_path, notice: "税率の変更を予約しました。", status: :see_other
  end

  private

  def planner
    TaxRateChangePlanner.new(current_account, from_rate: params[:from_rate], to_rate: params[:to_rate],
                                              keep: params[:keep] == "in_tax" ? "in_tax" : "ex_tax", excluded_category_ids: params[:excluded_category_ids])
  end

  def change_params
    params.require(:change).permit(:effective_on, :price, :tax_rate, :tax_type, :eat_in_price, :eat_in_tax_rate, :note).compact_blank
  end
end
