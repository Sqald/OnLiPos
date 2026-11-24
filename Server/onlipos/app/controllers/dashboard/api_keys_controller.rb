# 外部連携用のAPIキー（契約者のみ）
class Dashboard::ApiKeysController < Dashboard::BaseController
  requires_role read: "owner", write: "owner"
  before_action :require_recent_authentication, only: [ :create, :destroy ]

  def index
    @keys = current_account.api_keys.order(id: :desc)
  end

  def create
    key = current_account.api_keys.build(name: params.dig(:api_key, :name), scopes: Array(params.dig(:api_key, :scopes)).compact_blank)
    if key.save
      flash[:api_key] = key.token
      redirect_to dashboard_api_keys_path, notice: "APIキーを発行しました。", status: :see_other
    else
      redirect_to dashboard_api_keys_path, alert: key.errors.full_messages.join("、"), status: :see_other
    end
  end

  def destroy
    current_account.api_keys.find(params[:id]).revoke!
    redirect_to dashboard_api_keys_path, notice: "APIキーを無効にしました。", status: :see_other
  end
end
