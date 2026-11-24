# 要確認の会計（オフライン会計の価格相違・精算後の後着など）の一覧と確認
class Dashboard::SaleReviewsController < Dashboard::BaseController
  def index
    scope = Sale.where(user: current_account)
    scope = params[:reviewed] ? scope.where("review_reasons <> '[]'::jsonb").where.not(reviewed_at: nil) : scope.needing_review
    @sales = scope.includes(:store, :pos_token, :employee).order(sold_at: :desc).page(params[:page]).per(50)
  end

  def update
    sale = Sale.where(user: current_account).find(params[:id])
    sale.update_columns(reviewed_at: Time.current, reviewed_by_name: current_user.display_name)
    AuditLog.record("review", target: sale, details: { "レシート番号" => sale.receipt_number, "理由" => sale.review_reasons })
    redirect_to dashboard_sale_reviews_path, notice: "確認済みにしました。", status: :see_other
  end
end
