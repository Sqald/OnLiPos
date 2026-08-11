# POS端末の初期プロビジョニングデータ（店舗情報・税率・ハードウェア設定等）を管理する画面。
# ここで作成したデータをもとに、端末側の provisioning API で初期設定が行われる。
class Dashboard::ProvisioningsController < Dashboard::BaseController
  # プロビジョニング一覧
  def index
    @provisionings = Provisioning.where(user: current_user).order(created_at: :desc)
  end

  # 新規作成フォーム
  def new
    @provisioning = Provisioning.new
    @stores = current_user.stores
    @pos_tokens = PosToken.where(store: @stores)
  end

  # プロビジョニングデータを作成する。store_context（店舗情報・税率）と
  # hardware_settings（プリンタIP等）をJSONとして組み立てて保存する。
  def create
    @provisioning = Provisioning.new(provisioning_params)
    @provisioning.user = current_user

    # 店舗情報の取得とstore_contextの構築
    store = current_user.stores.find_by(id: provisioning_params[:store_id])
    if store
      store_mode = params.dig(:provisioning, :store_mode).presence || "standard"
      @provisioning.store_context = {
        store_id: store.id,
        store_name: store.name,
        store_mode: store_mode,
        tax_rate_standard: 0.10, # 将来的にはStoreモデル等から取得
        tax_rate_reduced: 0.08
      }
    else
      @provisioning.store_context = {}
    end

    # hardware_settingsの構築 (フォームからの入力をJSONに格納)
    hardware_params = params.require(:provisioning).permit(:receipt_printer_ip, :drawer_kick_command, :pos_role)
    @provisioning.hardware_settings = {
      receipt_printer_ip: hardware_params[:receipt_printer_ip],
      drawer_kick_command: hardware_params[:drawer_kick_command].presence || "27,112,0,50,250",
      pos_role: hardware_params[:pos_role].presence || "standard"
    }

    if @provisioning.save
      redirect_to dashboard_provisionings_path, notice: "プロビジョニングデータを作成しました。"
    else
      @stores = current_user.stores
      @pos_tokens = PosToken.where(store: @stores)
      render :new, status: :unprocessable_entity
    end
  end

  # プロビジョニングデータを削除する。自ユーザー配下のデータのみ対象。
  def destroy
    @provisioning = Provisioning.where(user: current_user).find_by(id: params[:id])
    if @provisioning
      @provisioning.destroy
      redirect_to dashboard_provisionings_path, notice: "削除しました。", status: :see_other
    else
      redirect_to dashboard_provisionings_path, alert: "権限がありません。"
    end
  end

  private

  # プロビジョニングフォームのStrong Parameters
  def provisioning_params
    params.require(:provisioning).permit(:name, :store_id)
  end
end
