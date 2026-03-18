class Dashboard::SaleDetailsController < Dashboard::BaseController
  def show
    @sale = Sale.where(user: current_user)
                .includes(:store, :pos_token, :saledetails, :sale_payments)
                .find(params[:id])
  end
end

