# 売上明細（レシート単位）の詳細表示画面。
class Dashboard::SaleDetailsController < Dashboard::BaseController
  # 自ユーザーの売上を明細・支払情報つきで取得して表示する
  def show
    @sale = Sale.where(user: current_user)
                .includes(:store, :pos_token, :saledetails, :sale_payments)
                .find(params[:id])
  end
end
