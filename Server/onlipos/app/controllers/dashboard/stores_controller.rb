class Dashboard::StoresController < Dashboard::BaseController
  before_action :set_store, only: [:edit, :update, :destroy, :prices, :update_prices]

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

  # 店舗別価格一覧・編集
  def prices
    @products = current_user.products.where(status: :active).order(:code)
    @prices_by_product_id = Price.where(store: @store).index_by(&:product_id)
  end

  # 店舗別価格の一括更新。送信された price_overrides を処理する。
  # 値が空またはデフォルト価格と同じ場合は store-specific 価格レコードを削除（デフォルトに戻す）。
  def update_prices
    Price.transaction do
      price_params = params[:price_overrides] || {}
      product_ids = price_params.keys.map(&:to_i)
      products_by_id = current_user.products.where(id: product_ids).index_by { |p| p.id.to_s }
      existing_prices = Price.where(store: @store, product_id: product_ids).index_by(&:product_id)

      price_params.each do |product_id_str, amount_str|
        product = products_by_id[product_id_str]
        next unless product

        price = existing_prices[product.id] || Price.new(store: @store, product: product)
        if amount_str.blank?
          price.destroy if price.persisted?
        else
          amount = amount_str.to_i
          if amount == product.price
            price.destroy if price.persisted?
          else
            price.amount = amount
            price.save!
          end
        end
      end
    end
    redirect_to prices_dashboard_store_path(@store), notice: "店舗別価格を更新しました。"
  rescue ActiveRecord::RecordInvalid => e
    @products = current_user.products.where(status: :active).order(:code)
    @prices_by_product_id = Price.where(store: @store).index_by(&:product_id)
    flash.now[:alert] = "更新に失敗しました: #{e.message}"
    render :prices, status: :unprocessable_entity
  end

  private

  def set_store
    @store = current_user.stores.find(params[:id])
  end

  def store_params
    params.require(:store).permit(:ascii_name, :name, :address, :phone_number, :description)
  end
end
