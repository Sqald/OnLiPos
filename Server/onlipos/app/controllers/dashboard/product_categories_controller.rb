class Dashboard::ProductCategoriesController < Dashboard::BaseController
  before_action :set_category, only: [:edit, :update, :destroy]

  def index
    @categories = current_user.product_categories.order(:display_order, :name)
  end

  def new
    @category = current_user.product_categories.build
  end

  def create
    @category = current_user.product_categories.build(category_params)
    if @category.save
      redirect_to dashboard_product_categories_path, notice: 'カテゴリを作成しました'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @category.update(category_params)
      redirect_to dashboard_product_categories_path, notice: 'カテゴリを更新しました'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @category.destroy
    redirect_to dashboard_product_categories_path, notice: 'カテゴリを削除しました'
  end

  private

  def set_category
    @category = current_user.product_categories.find(params[:id])
  end

  def category_params
    params.require(:product_category).permit(:name, :display_order)
  end
end
