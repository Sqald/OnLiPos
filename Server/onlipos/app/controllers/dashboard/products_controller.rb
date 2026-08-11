# 商品マスタの管理画面。商品の検索・登録・編集・削除に加え、CSVによる一括インポートを扱う。
class Dashboard::ProductsController < Dashboard::BaseController
  before_action :set_product, only: [ :edit, :update, :destroy ]

  # 商品一覧。キーワード（名前/コード）・ステータス・カテゴリで絞り込み検索できる
  def index
    scope = current_user.products.includes(:product_category)
    if params[:q].present?
      q = "%#{params[:q]}%"
      scope = scope.where("name ILIKE ? OR code ILIKE ?", q, q)
    end
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(product_category_id: params[:category_id]) if params[:category_id].present?
    @products = scope.order(:code).page(params[:page]).per(50)
    @categories = current_user.product_categories.order(:display_order, :name)
  end

  # 新規登録フォーム
  def new
    @product = current_user.products.build
  end

  # 商品を登録する
  def create
    @product = current_user.products.build(product_params)

    if @product.save
      redirect_to dashboard_products_path, notice: "商品を登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  # 編集フォーム
  def edit
  end

  # 商品情報を更新する
  def update
    if @product.update(product_params)
      redirect_to dashboard_products_path, notice: "商品情報を更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # 商品を削除する
  def destroy
    @product.destroy
    redirect_to dashboard_products_path, notice: "商品を削除しました。", status: :see_other
  end

  # アップロードされたCSVファイルを一時保存し、バックグラウンドジョブで商品を一括インポートする。
  # 多重実行を防ぐため Rails.cache でユーザー単位のロックを取る。
  def import
    if params[:file].blank?
      redirect_to dashboard_products_path, alert: "CSVファイルを選択してください。"
      return
    end

    lock_key = "product_import:user:#{current_user.id}"
    if Rails.cache.exist?(lock_key)
      redirect_to dashboard_products_path, alert: "現在インポート処理中です。完了後に再度お試しください。"
      return
    end

    # アップロードされたファイルを一時保存 (リクエスト終了後もJobから参照できるようにするため)
    uploaded_file = params[:file]
    file_path = Rails.root.join("tmp", "import_products_#{Time.now.to_i}_#{SecureRandom.hex(16)}.csv")
    Rails.cache.write(lock_key, true, expires_in: 30.minutes)
    IO.copy_stream(uploaded_file.tempfile, file_path)

    # バックグラウンドジョブを実行
    ProductImportJob.perform_later(file_path.to_s, current_user.id, lock_key)

    redirect_to dashboard_products_path, notice: "インポート処理を開始しました。完了までしばらくお待ちください。"
  end

  private

  # 自ユーザー配下の商品をIDで取得する
  def set_product
    @product = current_user.products.find(params[:id])
  end

  # 商品フォームのStrong Parameters
  def product_params
    params.require(:product).permit(:code, :name, :price, :description, :status, :tax_rate, :product_category_id)
  end
end
