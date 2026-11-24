# 商品のオプション（トッピング・サイズなど）
class Dashboard::OptionGroupsController < Dashboard::BaseController
  before_action :set_group, only: [ :edit, :update, :destroy ]

  def index
    @groups = current_account.option_groups.includes(:option_items, :products).order(:name)
  end

  def new
    @group = current_account.option_groups.build
    prepare_form
  end

  def create
    @group = current_account.option_groups.build(group_params)
    save("オプションを登録しました。", :new)
  end

  def edit = prepare_form

  def update
    @group.assign_attributes(group_params)
    save("オプションを変更しました。", :edit)
  end

  def destroy
    @group.destroy
    redirect_to dashboard_option_groups_path, notice: "削除しました。", status: :see_other
  end

  private

  def set_group
    @group = current_account.option_groups.find(params[:id])
  end

  # 入力欄として空の選択肢を数行用意する
  def prepare_form
    5.times { |i| @group.option_items.build(position: @group.option_items.size + i) }
  end

  def save(message, template)
    if @group.save
      redirect_to dashboard_option_groups_path, notice: message, status: :see_other
    else
      prepare_form
      render template, status: :unprocessable_entity
    end
  end

  def group_params
    params.require(:option_group).permit(:name, :min_select, :max_select, option_items_attributes: [ :id, :name, :price, :position, :_destroy ])
  end
end
