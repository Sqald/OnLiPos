# 電子レシートの公開ページ。URLに含まれる推測できないトークンで会計を特定する。
# 会員情報・担当者の氏名などの個人情報は表示しない。
class DigitalReceiptsController < ActionController::Base
  layout "public_page"

  rate_limit to: 60, within: 1.minute, with: -> { head :too_many_requests }

  def show
    @sale = Sale.includes(:store, :user, :saledetails, :sale_payments, :sale_tax_breakdowns, :refunds).find_by(public_token: params[:token].to_s)
    return render plain: "レシートが見つかりません", status: :not_found unless @sale&.user&.digital_receipt_enabled

    response.set_header("X-Robots-Tag", "noindex, nofollow")
    response.set_header("Referrer-Policy", "no-referrer")
    response.set_header("Cache-Control", "private, no-store")
  end
end
