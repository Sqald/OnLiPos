# 操作履歴の閲覧（契約者のみ）
class Dashboard::AuditLogsController < Dashboard::BaseController
  requires_role read: "owner", write: "owner"

  def index
    scope = current_account.audit_logs
    scope = scope.where(target_type: params[:target_type]) if AuditLog::TARGET_LABELS.key?(params[:target_type])
    scope = scope.where("actor_name ILIKE ?", "%#{AuditLog.sanitize_sql_like(params[:actor])}%") if params[:actor].present?
    if (from = parse_date(params[:from]))
      scope = scope.where(created_at: from.beginning_of_day..)
    end
    if (to = parse_date(params[:to]))
      scope = scope.where(created_at: ..to.end_of_day)
    end
    @logs = scope.order(created_at: :desc, id: :desc).page(params[:page]).per(100)
  end
end
