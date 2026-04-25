class Dashboard::RefundsController < Dashboard::BaseController
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

  def show
    @refund = Refund
      .joins(:sale)
      .where(sales: { user_id: current_user.id })
      .includes(:store, :pos_token, :refund_details, sale: :saledetails)
      .find(params[:id])
  end

  private

  def search_performed?
    params[:store_id].present? || params[:from].present? || params[:to].present?
  end
end
