# 在庫移動履歴（入出庫・移動）の閲覧画面。
class Dashboard::StockMovementsController < Dashboard::BaseController
  # 検索条件（店舗・期間）を指定して検索したときのみデータを取得する
  def index
    @stores = current_user.stores.order(:name)
    @allowed_store_ids = current_user.stores.pluck(:id)

    # 検索条件が1つも指定されていない場合はクエリを実行せず、空のページを返す（負荷軽減）
    unless search_performed?
      @movements = StockMovement.none.page(1).per(50)
      return
    end

    # 自ユーザー配下の店舗の在庫移動のみ（他ユーザーデータを絶対に含めない）
    scope = StockMovement
      .joins(:store)
      .where(stores: { user_id: current_user.id })

    if params[:store_id].present? && @allowed_store_ids.include?(params[:store_id].to_i)
      scope = scope.where(store_id: params[:store_id])
    end

    if params[:from].present?
      from_date = Date.parse(params[:from]) rescue nil
      scope = scope.where("stock_movements.created_at >= ?", from_date&.beginning_of_day) if from_date
    end

    if params[:to].present?
      to_date = Date.parse(params[:to]) rescue nil
      scope = scope.where("stock_movements.created_at <= ?", to_date&.end_of_day) if to_date
    end

    @movements = scope
      .includes(:store, :product, :sale, :employee, :pos_token)
      .order("stock_movements.created_at DESC")
      .page(params[:page])
      .per(50)
  end

  private

  # 検索条件（店舗・期間）のいずれかが指定されたかを判定する
  def search_performed?
    params[:store_id].present? || params[:from].present? || params[:to].present?
  end
end
