# 返金（返品）履歴の閲覧画面。
class Dashboard::RefundsController < Dashboard::BaseController
  # 返金一覧は検索条件（店舗・期間）を指定して検索したときのみデータを取得する。
  # 自ユーザーの売上に紐づく返金のみに厳格にスコープする。
  def index
    @stores = current_user.stores.order(:name)
    @allowed_store_ids = @stores.pluck(:id)

    unless search_performed?
      @refunds = Refund.none.page(1).per(50)
      return
    end

    scope = Refund
      .joins(:sale)
      .where(sales: { user_id: current_user.id })

    if params[:store_id].present? && @allowed_store_ids.include?(params[:store_id].to_i)
      scope = scope.where(store_id: params[:store_id])
    end

    if params[:from].present?
      from_time = Time.zone.parse(params[:from]) rescue nil
      scope = scope.where("refunds.created_at >= ?", from_time) if from_time
    end

    if params[:to].present?
      to_time = Time.zone.parse(params[:to])&.end_of_day rescue nil
      scope = scope.where("refunds.created_at <= ?", to_time) if to_time
    end

    @refunds = scope
      .includes(:store, :pos_token, sale: :pos_token)
      .order("refunds.created_at DESC")
      .page(params[:page])
      .per(50)
  end

  # 返金の詳細（元の売上明細・返金明細）を表示する
  def show
    @refund = Refund
      .joins(:sale)
      .where(sales: { user_id: current_user.id })
      .includes(:store, :pos_token, :refund_details, sale: :saledetails)
      .find(params[:id])
  end

  private

  # 検索条件（店舗・期間）のいずれかが指定されたかを判定する
  def search_performed?
    params[:store_id].present? || params[:from].present? || params[:to].present?
  end
end
