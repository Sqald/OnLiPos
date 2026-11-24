# お客様のスマートフォンからの注文（卓のQRコード）。ログイン不要。
# 金額はサーバーの商品マスタで決め、会計はレジで行う。
class SelfOrdersController < ActionController::Base
  layout "public_page"
  protect_from_forgery with: :exception
  rate_limit to: 30, within: 1.minute, only: :create, with: -> { redirect_to self_order_path(params[:token]), alert: "しばらくしてからもう一度お試しください。" }

  MAX_LINES = 30
  MAX_QUANTITY = 20

  before_action :set_table

  def show
    @request_id = SecureRandom.uuid
    @prices = Price.where(store: @store, product_id: @products.map(&:id)).pluck(:product_id, :amount).to_h
    @orders = @store.kitchen_orders.where(table_number: @table.table_number, created_at: 4.hours.ago..).where.not(status: :canceled).order(:id)
  end

  def create
    order = SelfOrder.new(@store, @table.table_number).place!(order_items, params[:request_id])
    redirect_to self_order_path(@table.token), notice: order ? "ご注文を受け付けました。" : "ご注文は受け付け済みです。", status: :see_other
  rescue SelfOrder::Error => e
    redirect_to self_order_path(@table.token), alert: e.message, status: :see_other
  end

  private

  def set_table
    @table = TableCode.includes(:store).find_by(token: params[:token].to_s, active: true)
    @store = @table&.store
    if @store.nil? || !@store.self_order_enabled || @store.user.suspended?
      return render plain: "現在このQRコードからはご注文いただけません。店員にお声がけください。", status: :not_found
    end

    @products = SelfOrder.menu(@store)
  end

  def order_items
    items = params[:items]
    return [] unless items.respond_to?(:to_unsafe_h)

    items.to_unsafe_h.first(200).filter_map do |product_id, attrs|
      next unless attrs.is_a?(Hash)

      quantity = attrs["quantity"].to_i
      next unless quantity.positive?

      { product_id: product_id.to_i, quantity: [ quantity, MAX_QUANTITY ].min, option_ids: Array(attrs["options"]).map(&:to_i) }
    end.first(MAX_LINES)
  end
end
