class Api::External::V1::SalesController < Api::External::V1::BaseController
  before_action { require_scope!("sales:read") }

  def index
    scope = date_range("sales.business_date", Sale.where(user: account)).includes(:store, :customer, :sale_payments, saledetails: :product)
    scope = scope.where(store_id: params[:store_id]) if params[:store_id].present?
    page = paginate(scope)
    render json: { sales: page[:records].map { |s| SalePayload.sale(s) }, next_after_id: page[:next_after_id] }
  end

  def show
    render json: { sale: SalePayload.sale(Sale.where(user: account).find(params[:id])) }
  end
end
