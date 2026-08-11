# セット商品（複数商品をまとめて1つの商品コードで販売する商品バンドル）の管理画面。
# バンドル本体と、その構成品目（product_bundle_items）をまとめて登録・更新する。
class Dashboard::ProductBundlesController < Dashboard::BaseController
  before_action :set_bundle, only: [ :edit, :update, :destroy ]

  # セット商品一覧
  def index
    @bundles = current_user.product_bundles.includes(:product_bundle_items).order(:code)
  end

  # 新規登録フォーム
  def new
    @bundle = current_user.product_bundles.build
    @products = current_user.products.active.order(:code)
  end

  # セット商品本体と構成品目を同一トランザクションで登録する
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

  # 編集フォーム
  def edit
    @products = current_user.products.active.order(:code)
  end

  # セット商品本体を更新し、構成品目は一旦削除してから作り直す
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

  # セット商品を削除する
  def destroy
    @bundle.destroy
    redirect_to dashboard_product_bundles_path, notice: "セット商品を削除しました。"
  end

  private

  # 自ユーザー配下のセット商品をIDで取得する
  def set_bundle
    @bundle = current_user.product_bundles.find(params[:id])
  end

  # セット商品本体フォームのStrong Parameters
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
