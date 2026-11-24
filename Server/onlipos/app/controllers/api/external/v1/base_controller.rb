# 外部連携用APIの基底クラス。APIキー（Authorization: Bearer）で認証し、キーの権限（scope）を確認する。
class Api::External::V1::BaseController < Api::BaseController
  rate_limit to: 300, within: 1.minute, by: -> { ApiKey.digest(request.authorization.to_s) }, with: -> { render json: { error: "rate_limited" }, status: :too_many_requests }
  before_action :authenticate_api_key
  rescue_from(ActiveRecord::RecordNotFound) { render json: { error: "not_found" }, status: :not_found }
  rescue_from(Date::Error, ActionController::ParameterMissing) { |e| render json: { error: "bad_request", message: e.message }, status: :bad_request }

  MAX_PER_PAGE = 100

  private

  attr_reader :api_key

  def authenticate_api_key
    @api_key = ApiKey.authenticate(request.authorization.to_s[/\ABearer (.+)\z/, 1])
    return render(json: { error: "unauthorized" }, status: :unauthorized) if api_key.nil? || api_key.user.suspended?

    api_key.update_columns(last_used_at: Time.current) if api_key.last_used_at.nil? || api_key.last_used_at < 10.minutes.ago
    Current.account = account
    Current.actor = api_key
    Current.ip_address = request.remote_ip
  end

  def require_scope!(scope)
    render json: { error: "insufficient_scope", required: scope }, status: :forbidden unless api_key.scopes.include?(scope)
  end

  def account = api_key.user

  # after_id によるカーソル式ページング
  def paginate(scope)
    limit = (params[:limit].presence || 50).to_i.clamp(1, MAX_PER_PAGE)
    records = scope.where("#{scope.table_name}.id > ?", params[:after_id].to_i).reorder(:id).limit(limit + 1).to_a
    { records: records.first(limit), next_after_id: (records[limit - 1].id if records.size > limit) }
  end

  def date_range(column, scope)
    scope = scope.where(column => Date.iso8601(params[:from].to_s)..) if params[:from].present?
    scope = scope.where(column => ..Date.iso8601(params[:to].to_s)) if params[:to].present?
    scope
  end
end
