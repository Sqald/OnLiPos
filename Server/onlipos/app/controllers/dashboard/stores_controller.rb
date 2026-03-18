class Dashboard::StoresController < Dashboard::BaseController
  before_action :set_store, only: [:edit, :update, :destroy]

  def index
    @stores = current_user.stores.order(created_at: :desc)
  end

  def new
    @store = Store.new
  end

  def create
    @store = current_user.stores.build(store_params)

    if @store.save
      redirect_to dashboard_stores_path, notice: "店舗を登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @store.update(store_params)
      redirect_to dashboard_stores_path, notice: "店舗情報を更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @store.destroy
    redirect_to dashboard_stores_path, notice: "店舗を削除しました。", status: :see_other
  end

  private

  def set_store
    @store = current_user.stores.find(params[:id])
  end

  def store_params
    params.require(:store).permit(:ascii_name, :name, :address, :phone_number, :description)
  end
end
