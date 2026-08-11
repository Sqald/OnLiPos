# 商品カテゴリの管理画面。カテゴリの登録・編集・削除、表示順（display_order）の管理を行う。
class Dashboard::ProductCategoriesController < Dashboard::BaseController
  before_action :set_category, only: [ :edit, :update, :destroy ]

  # 表示順・名前順のカテゴリ一覧
  def index
    @categories = current_user.product_categories.order(:display_order, :name)
  end

  # 新規登録フォーム
  def new
    @category = current_user.product_categories.build
  end

  # カテゴリを登録する
  def create
    @category = current_user.product_categories.build(category_params)
    if @category.save
      redirect_to dashboard_product_categories_path, notice: "カテゴリを作成しました"
    else
      render :new, status: :unprocessable_entity
    end
  end

  # 編集フォーム
  def edit; end

  # カテゴリを更新する
  def update
    if @category.update(category_params)
      redirect_to dashboard_product_categories_path, notice: "カテゴリを更新しました"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # カテゴリを削除する
  def destroy
    @category.destroy
    redirect_to dashboard_product_categories_path, notice: "カテゴリを削除しました"
  end

  private

  # 自ユーザー配下のカテゴリをIDで取得する
  def set_category
    @category = current_user.product_categories.find(params[:id])
  end

  # カテゴリフォームのStrong Parameters
  def category_params
    params.require(:product_category).permit(:name, :display_order)
  end
end
