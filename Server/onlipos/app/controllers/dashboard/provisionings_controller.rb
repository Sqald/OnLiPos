class Dashboard::ProvisioningsController < Dashboard::BaseController
  def index
    @provisionings = Provisioning.where(user: current_user).order(created_at: :desc)
  end

  def new
    @provisioning = Provisioning.new
    @stores = current_user.stores
    @pos_tokens = PosToken.where(store: @stores)
  end

  def create
    @provisioning = Provisioning.new(provisioning_params)
    @provisioning.user = current_user

    # 店舗情報の取得とstore_contextの構築
    store = current_user.stores.find_by(id: provisioning_params[:store_id])
    if store
      @provisioning.store_context = {
        store_id: store.id,
        store_name: store.name,
        tax_rate_standard: 0.10, # 将来的にはStoreモデル等から取得
        tax_rate_reduced: 0.08
      }
    else
      @provisioning.store_context = {}
    end

    # hardware_settingsの構築 (フォームからの入力をJSONに格納)
    hardware_params = params.require(:provisioning).permit(:receipt_printer_ip, :drawer_kick_command)
    @provisioning.hardware_settings = {
      receipt_printer_ip: hardware_params[:receipt_printer_ip],
      drawer_kick_command: hardware_params[:drawer_kick_command].presence || "27,112,0,50,250"
    }

    if @provisioning.save
      redirect_to dashboard_provisionings_path, notice: 'プロビジョニングデータを作成しました。'
    else
      @stores = current_user.stores
      @pos_tokens = PosToken.where(store: @stores)
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @provisioning = Provisioning.where(user: current_user).find_by(id: params[:id])
    if @provisioning
      @provisioning.destroy
      redirect_to dashboard_provisionings_path, notice: '削除しました。', status: :see_other
    else
      redirect_to dashboard_provisionings_path, alert: '権限がありません。'
    end
  end

  private

  def provisioning_params
    params.require(:provisioning).permit(:name, :store_id)
  end
end