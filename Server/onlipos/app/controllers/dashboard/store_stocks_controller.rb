# 店舗在庫の照会・調整画面。JANコードで在庫を検索し、店舗間の在庫移動や
# 数量の手動調整を行う。変更内容は StockMovement に監査ログとして記録される。
class Dashboard::StoreStocksController < Dashboard::BaseController
  before_action :set_store_stock, only: [ :update ]

  # 店舗間在庫移動
  def transfer
    from_store = current_account.stores.find_by(id: params[:from_store_id])
    to_store   = current_account.stores.find_by(id: params[:to_store_id])
    product    = current_account.products.find_by(code: params[:jan_code].to_s.strip)
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

    # 移動元は減算・移動先は加算し、それぞれ行ロックの上でStockMovementに記録する
    ActiveRecord::Base.transaction do
      StoreStock.adjust!(store: from_store, product: product, change: -quantity, reason: "transfer_out")
      StoreStock.adjust!(store: to_store, product: product, change: quantity, reason: "transfer_in")
    end
    AuditLog.record("update", target: product, details: { "操作" => "店舗間の在庫移動", "数量" => quantity, "移動元" => from_store.name, "移動先" => to_store.name })

    redirect_back fallback_location: dashboard_store_stocks_path,
                  notice: "#{product.name} を #{from_store.name} から #{to_store.name} へ #{quantity} 個移動しました。"
  rescue ActiveRecord::Rollback => e
    redirect_back fallback_location: dashboard_store_stocks_path, alert: e.message.presence || "移動に失敗しました。"
  end

  # 店舗在庫一覧画面。商品名・コードと店舗で絞り込める。
  # jan_code（商品コード）を指定したときは、その商品の店舗別の在庫を表示し、数量の変更・店舗間の移動ができる。
  def index
    @stores = current_account.stores.order(:name)
    @jan_code = params[:jan_code].to_s.strip

    if @jan_code.present?
      @product = current_account.products.find_by(code: @jan_code)
      @store_stocks = @product ? StoreStock.joins(:store).includes(:store).where(store: current_account.stores, product: @product).order("stores.name ASC") : []
      return
    end

    scope = StoreStock.joins(:store, :product).includes(:store, :product).where(store: current_account.stores)
    scope = scope.where(store_id: params[:store_id]) if params[:store_id].present?
    if params[:q].present?
      q = "%#{Product.sanitize_sql_like(params[:q].strip)}%"
      scope = scope.where("products.name ILIKE :q OR products.code ILIKE :q", q: q)
    end
    @stocks = scope.order("products.code", "stores.name").page(params[:page]).per(50)
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

    AuditLog.record("update", target: @store_stock, details: { "商品" => @store_stock.product.name, "店舗" => @store_stock.store.name, "数量" => new_quantity })
    redirect_back fallback_location: dashboard_store_stocks_path(jan_code: params[:jan_code]), notice: "在庫数量を更新しました。"
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: dashboard_store_stocks_path(jan_code: params[:jan_code]), alert: e.message
  end

  private

  # 自ユーザー配下の店舗在庫をIDで取得する
  def set_store_stock
    @store_stock = StoreStock
      .joins(:store)
      .where(stores: { user_id: current_account.id })
      .find(params[:id])
  end
end
