class Dashboard::StoreStocksController < Dashboard::BaseController
  before_action :set_store_stock, only: [:update]

  # 店舗間在庫移動
  def transfer
    from_store = current_user.stores.find_by(id: params[:from_store_id])
    to_store   = current_user.stores.find_by(id: params[:to_store_id])
    product    = current_user.products.find_by(code: params[:jan_code].to_s.strip)
    quantity   = params[:quantity].to_i

    if from_store.nil? || to_store.nil?
      redirect_back fallback_location: dashboard_store_stocks_path, alert: "移動元・移動先店舗が不正です。"
      return
    end
    if from_store.id == to_store.id
      redirect_back fallback_location: dashboard_store_stocks_path, alert: "移動元と移動先が同じ店舗です。"
      return
    end
    if product.nil?
      redirect_back fallback_location: dashboard_store_stocks_path, alert: "商品が見つかりません。"
      return
    end
    if quantity <= 0
      redirect_back fallback_location: dashboard_store_stocks_path, alert: "移動数量は1以上を入力してください。"
      return
    end

    ActiveRecord::Base.transaction do
      from_stock = StoreStock.find_or_create_by!(store: from_store, product: product)
      from_stock.with_lock do
        raise ActiveRecord::Rollback, "在庫不足です。" if from_stock.quantity < quantity
        from_stock.decrement!(:quantity, quantity)
        StockMovement.create!(
          store: from_store, product: product, store_stock: from_stock,
          quantity_change: -quantity, reason: "transfer_out"
        )
      end

      to_stock = StoreStock.find_or_create_by!(store: to_store, product: product)
      to_stock.with_lock do
        to_stock.increment!(:quantity, quantity)
        StockMovement.create!(
          store: to_store, product: product, store_stock: to_stock,
          quantity_change: quantity, reason: "transfer_in"
        )
      end
    end

    redirect_back fallback_location: dashboard_store_stocks_path,
                  notice: "#{product.name} を #{from_store.name} から #{to_store.name} へ #{quantity} 個移動しました。"
  rescue ActiveRecord::Rollback => e
    redirect_back fallback_location: dashboard_store_stocks_path, alert: e.message.presence || "移動に失敗しました。"
  end

  # 店舗在庫一覧画面。
  # 初期表示時は一覧を出さず、JANコードで検索された場合のみ表示する。
  def index
    @jan_code = params[:jan_code].to_s.strip
    @product = nil
    @store_stocks = []

    return if @jan_code.blank?

    @product = current_user.products.find_by(code: @jan_code)
    return unless @product

    @store_stocks = StoreStock
      .includes(:store)
      .where(store: current_user.stores, product: @product)
      .order("stores.name ASC")
  end

  # 一覧から店舗ごとの在庫数量を直接更新する。変更差分を StockMovement に記録する。
  def update
    quantity = params[:store_stock].try(:[], :quantity)

    if quantity.nil?
      redirect_back fallback_location: dashboard_store_stocks_path, alert: "数量を入力してください。"
      return
    end

    new_quantity = quantity.to_i

    ActiveRecord::Base.transaction do
      @store_stock.lock!
      old_quantity = @store_stock.quantity.to_i
      diff = new_quantity - old_quantity
      @store_stock.update!(quantity: new_quantity)
      if diff != 0
        StockMovement.create!(
          store: @store_stock.store,
          product: @store_stock.product,
          store_stock: @store_stock,
          quantity_change: diff,
          reason: "manual_adjustment"
        )
      end
    end

    redirect_back fallback_location: dashboard_store_stocks_path(jan_code: params[:jan_code]), notice: "在庫数量を更新しました。"
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: dashboard_store_stocks_path(jan_code: params[:jan_code]), alert: e.message
  end

  private

  def set_store_stock
    @store_stock = StoreStock
      .joins(:store)
      .where(stores: { user_id: current_user.id })
      .find(params[:id])
  end
end

