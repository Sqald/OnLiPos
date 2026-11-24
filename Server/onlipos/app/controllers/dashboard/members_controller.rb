# ダッシュボードのメンバー管理（契約者のみ）。役割ごとに操作範囲を分ける。
class Dashboard::MembersController < Dashboard::BaseController
  requires_role read: "owner", write: "owner"
  before_action :require_recent_authentication, except: [ :index ]
  before_action :set_member, only: [ :update, :destroy, :reset_password ]

  ROLE_LABELS = { "owner" => "契約者", "manager" => "管理者（店舗運営全般）", "viewer" => "閲覧のみ" }.freeze
  helper_method :role_label

  def index
    @members = current_account.members.order(:created_at)
  end

  def new
    @member = User.new(role: :manager)
  end

  def create
    password = generated_password
    @member = User.new(member_params.merge(owner: current_account, user_type: :individual, password: password,
                                           password_confirmation: password))
    @member.role = params.dig(:user, :role).presence_in(%w[manager viewer]) || "viewer"
    @member.skip_confirmation! if @member.respond_to?(:skip_confirmation!)

    if @member.save
      AuditLog.record("security", target: @member, details: { "操作" => "メンバーを追加" })
      flash[:member_password] = password
      redirect_to dashboard_members_path, notice: "メンバー「#{@member.display_name}」を追加しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @member.update!(role: params.dig(:user, :role).presence_in(%w[manager viewer]) || @member.role)
    @member.revoke_sessions!
    redirect_to dashboard_members_path, notice: "役割を変更しました（次の操作から再ログインが必要です）。", status: :see_other
  end

  # 初期パスワードを作り直し、2段階認証も解除する（端末の紛失・引き継ぎ時）
  def reset_password
    password = generated_password
    @member.update!(password: password, password_confirmation: password)
    @member.reset_mfa!
    AuditLog.record("security", target: @member, details: { "操作" => "パスワード・2段階認証をリセット" })
    flash[:member_password] = password
    redirect_to dashboard_members_path, notice: "「#{@member.display_name}」のパスワードを再発行しました。", status: :see_other
  end

  def destroy
    @member.destroy!
    redirect_to dashboard_members_path, notice: "メンバーを削除しました。", status: :see_other
  end

  private

  def set_member
    @member = current_account.members.find(params[:id])
  end

  def member_params
    params.require(:user).permit(:login_name, :email, :last_name, :first_name)
  end

  def generated_password = SecureRandom.base58(16)

  def role_label(role) = ROLE_LABELS.fetch(role.to_s, role)
end
