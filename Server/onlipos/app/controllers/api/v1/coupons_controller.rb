# クーポンの確認（会計前に割引内容を表示する）
class Api::V1::CouponsController < Api::V1::BaseController
  def show
    coupon = @current_pos.store.user.coupons.find_by(code: params[:id].to_s.strip.upcase)
    return render json: { success: false, message: "クーポンが見つかりません" }, status: :not_found unless coupon

    total = params[:total].to_i
    if (reason = coupon.unusable_reason(total))
      return render json: { success: false, message: reason }, status: :unprocessable_entity
    end

    render json: { success: true, coupon: { code: coupon.code, name: coupon.name, discount_type: coupon.discount_type, discount_value: coupon.discount_value, discount: coupon.discount_for(total) } }
  end
end
