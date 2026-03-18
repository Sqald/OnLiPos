class Dashboard::PosDevicesController < Dashboard::BaseController
  def new
    @pos_token = PosToken.new
    @stores = current_user.stores
    # 表示上は全店舗分を出すが、実際の紐付けはcreate側で
    # 「同じ店舗のプロビジョニングのみ」を許可する。
    @provisionings = current_user.provisionings.order(created_at: :desc)
  end

  def create
    @store = current_user.stores.find_by(id: pos_token_params[:store_id])

    if @store.nil?
      @stores = current_user.stores
      @provisionings = current_user.provisionings.order(created_at: :desc)
      flash.now[:alert] = "店舗を選択してください。"
      @pos_token = PosToken.new(pos_token_params.except(:store_id))
      render :new, status: :unprocessable_entity
      return
    end

    @pos_token = @store.pos_tokens.build(pos_token_params.except(:store_id))

    generated_password = SecureRandom.random_number(100000..999999).to_s
    @pos_token.password = generated_password
    @pos_token.password_confirmation = generated_password

    if @pos_token.save
      flash[:notice] = "POS端末「#{@pos_token.name}」を登録しました。パスワード: #{generated_password} (※このパスワードは再表示されませんので必ず控えてください)"
      redirect_to dashboard_root_path
    else
      @stores = current_user.stores
      @provisionings = current_user.provisionings.order(created_at: :desc)
      render :new, status: :unprocessable_entity
    end
  end

  def update_password
    @pos_token = PosToken.joins(:store)
                         .where(stores: { user_id: current_user.id })
                         .find_by(id: params[:pos_device_id])

    unless @pos_token
      redirect_to dashboard_root_path, alert: "権限がありません。", status: :see_other
      return
    end

    new_password = SecureRandom.random_number(100000..999999).to_s
    @pos_token.password = new_password
    @pos_token.password_confirmation = new_password

    if @pos_token.save
      @pos_token.regenerate_token
      msg = "POS端末「#{@pos_token.name}」のパスワードを再設定しました。\n新パスワード: #{new_password}\n(※メモしてください)"
      redirect_to dashboard_root_path, notice: msg, status: :see_other
    else
      redirect_to dashboard_root_path, alert: "パスワードの更新に失敗しました。", status: :see_other
    end
  end

  private

  def pos_token_params
    params.require(:pos_token).permit(:ascii_name,:name, :store_id, :provisioning_id)
  end
end
