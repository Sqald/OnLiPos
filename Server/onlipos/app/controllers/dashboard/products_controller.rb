# 商品マスタの管理画面。商品の検索・登録・編集・削除に加え、CSVによる一括インポートを扱う。
class Dashboard::ProductsController < Dashboard::BaseController
  before_action :set_product, only: [ :edit, :update, :destroy ]

  # 商品一覧。キーワード（名前/コード）・ステータス・カテゴリで絞り込み検索できる
  def index
    scope = current_account.products.includes(:product_category)
    if params[:q].present?
      q = "%#{Product.sanitize_sql_like(params[:q])}%"
      scope = scope.where("name ILIKE ? OR code ILIKE ?", q, q)
    end
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(product_category_id: params[:category_id]) if params[:category_id].present?
    @products = scope.order(:code).page(params[:page]).per(50)
    @categories = current_account.product_categories.order(:display_order, :name)
    @imports = current_account.product_imports.order(id: :desc).limit(5)
  end

  # 新規登録フォーム
  def new
    @product = current_account.products.build
  end

  # 商品を登録する
  def create
    @product = current_account.products.build(product_params)

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
    if @product.destroy
      redirect_to dashboard_products_path, notice: "商品を削除しました。", status: :see_other
    else
      redirect_to dashboard_products_path, status: :see_other,
                  alert: "販売履歴がある商品は削除できません。ステータスを「廃盤」にしてください。"
    end
  rescue ActiveRecord::InvalidForeignKey
    redirect_to dashboard_products_path, status: :see_other,
                alert: "返品・入出庫・セット商品などで参照されているため、この商品は削除できません。ステータスを「廃盤」にしてください。"
  end

  # アップロードされたCSVを、バックグラウンドジョブで一括インポートする。
  def import
    if params[:file].blank?
      redirect_to dashboard_products_path, alert: "CSVファイルを選択してください。"
      return
    end

    if current_account.product_imports.unfinished.exists?
      return redirect_to dashboard_products_path, alert: "現在インポート処理中です。完了後に再度お試しください。"
    end
    if params[:file].size > ProductImport::MAX_SIZE
      return redirect_to dashboard_products_path, alert: "CSVファイルは5MB以内にしてください。"
    end

    import = current_account.product_imports.create!(filename: params[:file].original_filename.to_s.slice(0, 200),
                                                     content: ProductImport.decode(params[:file].read))
    AuditLog.record("create", details: { "操作" => "商品CSVの取込", "ファイル" => import.filename })
    ProductImportJob.perform_later(import)
    redirect_to dashboard_products_path, notice: "インポート処理を開始しました。結果はこの画面の「取込の履歴」で確認できます。"
  rescue EncodingError
    redirect_to dashboard_products_path, alert: "CSVの文字コードを判別できません。UTF-8 または Shift_JIS で保存してください。"
  end

  # 商品画像（契約のデータとして認証付きで表示する）
  def image
    product = current_account.products.find(params[:id])
    return head :not_found unless product.image.attached?

    send_data product.image.download, type: product.image.content_type, disposition: "inline"
  end

  # 商品マスタをCSVで出力する（編集してそのまま取り込める）
  def export
    AuditLog.record("export", details: { "操作" => "商品CSVの出力" })
    send_data Product.export_csv(current_account.products), filename: "products_#{Date.current}.csv", type: "text/csv; charset=UTF-8"
  end

  private

  # 自ユーザー配下の商品をIDで取得する
  def set_product
    @product = current_account.products.find(params[:id])
  end

  # 商品フォームのStrong Parameters
  def product_params
    params.require(:product).permit(:code, :name, :price, :description, :status, :tax_rate, :product_category_id, :sold_by_weight, :tax_type, :cost_price,
                                    :eat_in_tax_rate, :eat_in_price, :min_age, :low_stock_threshold, :variant_group, :variant_name,
                                    :track_stock, :supplier_id, :image, option_group_ids: []).tap do |p|
      # 他の契約のオプションを紐付けられないようにする
      p[:option_group_ids] = current_account.option_groups.where(id: p[:option_group_ids]).ids if p.key?(:option_group_ids)
      # 無効な画像（未選択）で既存の画像を消さない
      p.delete(:image) if p[:image].blank?
    end
  end
end
