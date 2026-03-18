class Dashboard::SalesController < Dashboard::BaseController
  # 売上一覧は検索条件（店舗・期間）を指定して検索したときのみデータを取得する。
  # 自ユーザー（current_user）の売上のみに厳格にスコープする。
  def index
    @stores = current_user.stores.order(:name)
    @allowed_store_ids = current_user.stores.pluck(:id)

    unless search_performed?
      @sales = Sale.none.page(1).per(50)
      return
    end

    scope = Sale.where(user_id: current_user.id)

    if params[:store_id].present? && @allowed_store_ids.include?(params[:store_id].to_i)
      scope = scope.where(store_id: params[:store_id])
    end

    if params[:from].present?
      from_time = Time.zone.parse(params[:from]) rescue nil
      scope = scope.where("created_at >= ?", from_time) if from_time
    end

    if params[:to].present?
      to_time = Time.zone.parse(params[:to])&.end_of_day rescue nil
      scope = scope.where("created_at <= ?", to_time) if to_time
    end

    @sales = scope
      .includes(:store, :pos_token, :sale_payments)
      .order(created_at: :desc)
      .page(params[:page])
      .per(50)
  end

  private

  def search_performed?
    params[:store_id].present? || params[:from].present? || params[:to].present?
  end
end
