# POS端末（pos_token）の管理画面。端末の新規登録・削除・パスワード再発行を扱う。
# 端末はプロビジョニングデータと紐づけて登録される。
class Dashboard::PosDevicesController < Dashboard::BaseController
  # 店舗ごとの端末一覧と稼働状況
  def index
    @stores = current_account.stores.includes(:pos_tokens).order(:name)
  end

  # 新規登録フォーム
  def new
    @pos_token = PosToken.new(store_id: params[:store_id])
    @stores = current_account.stores
    # 表示上は全店舗分を出すが、実際の紐付けはcreate側で
    # 「同じ店舗のプロビジョニングのみ」を許可する。
    @provisionings = current_account.provisionings.order(created_at: :desc)
  end

  # POS端末を登録する。パスワードはランダム生成し、初回のみ画面に表示する。
  def create
    @store = current_account.stores.find_by(id: pos_token_params[:store_id])

    if @store.nil?
      @stores = current_account.stores
      @provisionings = current_account.provisionings.order(created_at: :desc)
      flash.now[:alert] = "店舗を選択してください。"
      @pos_token = PosToken.new(pos_token_params.except(:store_id))
      render :new, status: :unprocessable_entity
      return
    end

    @pos_token = @store.pos_tokens.build(pos_token_params.except(:store_id))

    generated_password = @pos_token.issue_initial_password

    if @pos_token.save
      flash[:notice] = "POS端末「#{@pos_token.name}」を登録しました。パスワード: #{generated_password} " \
                       "（有効期限: #{I18n.l(@pos_token.password_expires_at, format: '%Y/%m/%d %H:%M')}まで。※このパスワードは再表示されませんので必ず控えてください）"
      redirect_to dashboard_pos_devices_path
    else
      @stores = current_account.stores
      @provisionings = current_account.provisionings.order(created_at: :desc)
      render :new, status: :unprocessable_entity
    end
  end

  # POS端末を削除する。自ユーザー配下の端末のみが対象。
  def destroy
    @pos_token = PosToken.joins(:store)
                         .where(stores: { user_id: current_account.id })
                         .find(params[:id])
    name = @pos_token.name
    @pos_token.destroy!
    redirect_to dashboard_pos_devices_path, notice: "POS端末「#{name}」を削除しました。", status: :see_other
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_pos_devices_path, alert: "端末が見つかりません。", status: :see_other
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey, ActiveRecord::NotNullViolation
    redirect_to dashboard_pos_devices_path, status: :see_other,
                alert: "売上・レジ精算などの履歴がある端末は削除できません（取引記録の保存のため）。端末を紛失した場合は「停止」を使ってください。"
  rescue => e
    Rails.logger.error "POS token destroy failed: #{e.message}"
    redirect_to dashboard_pos_devices_path, alert: "削除に失敗しました。時間をおいて再試行してください。", status: :see_other
  end

  # 端末の遠隔停止（紛失・盗難時）。履歴は残る
  def disable
    owned_device.disable!(params[:reason])
    redirect_to dashboard_pos_devices_path, notice: "POS端末「#{owned_device.name}」を停止しました。", status: :see_other
  end

  def enable
    owned_device.enable!
    redirect_to dashboard_pos_devices_path, notice: "POS端末「#{owned_device.name}」の停止を解除しました。", status: :see_other
  end

  # POS端末のパスワードを再発行する。新パスワードはランダム生成し、画面に一度だけ表示する。
  def update_password
    @pos_token = PosToken.joins(:store)
                         .where(stores: { user_id: current_account.id })
                         .find_by(id: params[:pos_device_id])

    unless @pos_token
      redirect_to dashboard_pos_devices_path, alert: "権限がありません。", status: :see_other
      return
    end

    new_password = @pos_token.issue_initial_password

    if @pos_token.save
      @pos_token.regenerate_token
      msg = "POS端末「#{@pos_token.name}」のパスワードを再設定しました。\n新パスワード: #{new_password}\n" \
            "有効期限: #{I18n.l(@pos_token.password_expires_at, format: '%Y/%m/%d %H:%M')}まで（期限内に端末で認証してください）\n(※メモしてください)"
      redirect_to dashboard_pos_devices_path, notice: msg, status: :see_other
    else
      redirect_to dashboard_pos_devices_path, alert: "パスワードの更新に失敗しました。", status: :see_other
    end
  end

  private

  def owned_device
    @owned_device ||= PosToken.joins(:store).where(stores: { user_id: current_account.id }).find(params[:id])
  end

  # POS端末フォームのStrong Parameters
  def pos_token_params
    params.require(:pos_token).permit(:ascii_name, :name, :store_id, :provisioning_id)
  end
end
