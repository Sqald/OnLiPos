class Dashboard::ProductBundlesController < Dashboard::BaseController
  before_action :set_bundle, only: [:edit, :update, :destroy]

  def index
    @bundles = current_user.product_bundles.includes(:product_bundle_items).order(:code)
  end

  def new
    @bundle = current_user.product_bundles.build
    @products = current_user.products.active.order(:code)
  end

  def create
    @bundle = current_user.product_bundles.build(bundle_params)
    ActiveRecord::Base.transaction do
      @bundle.save!
      save_items(@bundle)
    end
    redirect_to dashboard_product_bundles_path, notice: "セット商品を登録しました。"
  rescue ActiveRecord::RecordInvalid
    @products = current_user.products.active.order(:code)
    render :new, status: :unprocessable_entity
  end

  def edit
    @products = current_user.products.active.order(:code)
  end

  def update
    if @bundle.update(bundle_params)
      ActiveRecord::Base.transaction do
        @bundle.product_bundle_items.destroy_all
        save_items(@bundle)
      end
      redirect_to dashboard_product_bundles_path, notice: "セット商品を更新しました。"
    else
      @products = current_user.products.active.order(:code)
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    @products = current_user.products.active.order(:code)
    flash.now[:alert] = "アイテムの保存に失敗しました: #{e.message}"
    render :edit, status: :unprocessable_entity
  end

  def destroy
    @bundle.destroy
    redirect_to dashboard_product_bundles_path, notice: "セット商品を削除しました。"
  end

  private

  def set_bundle
    @bundle = current_user.product_bundles.find(params[:id])
  end

  def bundle_params
    params.require(:product_bundle).permit(:code, :name, :price, :status)
  end

  # フォームから items[n][product_id] / items[n][quantity] を受け取る
  def save_items(bundle)
    items = params[:items]
    return unless items.is_a?(Array)

    items.each do |item|
      pid = item[:product_id].to_i
      qty = item[:quantity].to_i
      next if pid <= 0 || qty <= 0
      product = current_user.products.find_by(id: pid)
      next unless product
      bundle.product_bundle_items.create!(product: product, quantity: qty)
    end
  end
end
