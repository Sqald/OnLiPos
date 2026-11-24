# 発注・入荷
class Dashboard::PurchaseOrdersController < Dashboard::BaseController
  before_action :set_order, only: [ :show, :edit, :update, :destroy, :place, :receive, :cancel ]
  before_action :set_form_choices, only: [ :new, :create, :edit, :update ]
  rescue_from(PurchaseOrder::Error) { |e| redirect_to dashboard_purchase_order_path(@order), alert: e.message, status: :see_other }

  def index
    scope = current_account.purchase_orders.includes(:store, :supplier, :items)
    scope = scope.where(status: params[:status]) if PurchaseOrder.statuses.key?(params[:status])
    @orders = scope.order(id: :desc).page(params[:page]).per(50)
  end

  def show; end

  # 在庫が不足している商品を、仕入先ごとの発注の初期値にする
  def new
    @order = current_account.purchase_orders.build(store_id: params[:store_id], supplier_id: params[:supplier_id])
    if @order.store && @order.supplier
      current_account.products.active.where(supplier: @order.supplier).where.not(low_stock_threshold: nil).find_each do |product|
        quantity = StoreStock.find_by(store: @order.store, product: product)&.quantity.to_i
        @order.items.build(product: product, quantity: product.low_stock_threshold * 2 - quantity, unit_cost: product.cost_price.to_i) if quantity <= product.low_stock_threshold
      end
    end
    5.times { @order.items.build }
  end

  def create
    @order = current_account.purchase_orders.build(order_params)
    if @order.save
      redirect_to dashboard_purchase_order_path(@order), notice: "発注を作成しました。", status: :see_other
    else
      5.times { @order.items.build }
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    return redirect_to(dashboard_purchase_order_path(@order), alert: "下書きの発注のみ変更できます。") unless @order.draft?
    5.times { @order.items.build }
  end

  def update
    raise PurchaseOrder::Error, "下書きの発注のみ変更できます" unless @order.draft?
    if @order.update(order_params)
      redirect_to dashboard_purchase_order_path(@order), notice: "変更しました。", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    raise PurchaseOrder::Error, "下書きの発注のみ削除できます" unless @order.draft?
    @order.destroy!
    redirect_to dashboard_purchase_orders_path, notice: "削除しました。", status: :see_other
  end

  def place
    @order.place!
    redirect_to dashboard_purchase_order_path(@order), notice: "発注を確定しました。", status: :see_other
  end

  def receive
    received = params[:received]
    @order.receive!(received.respond_to?(:to_unsafe_h) ? received.to_unsafe_h : {})
    redirect_to dashboard_purchase_order_path(@order), notice: "入荷を登録し、在庫に加算しました。", status: :see_other
  end

  def cancel
    @order.cancel!
    redirect_to dashboard_purchase_order_path(@order), notice: "発注を取り消しました。", status: :see_other
  end

  private

  def set_order
    @order = current_account.purchase_orders.find(params[:id])
  end

  def set_form_choices
    @stores = current_account.stores.order(:name)
    @suppliers = current_account.suppliers.where(active: true).order(:name)
    @products = current_account.products.active.order(:code)
  end

  def order_params
    params.require(:purchase_order).permit(:store_id, :supplier_id, :expected_on, :note, items_attributes: [ :id, :product_id, :quantity, :unit_cost, :_destroy ])
  end
end
