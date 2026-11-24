# 棚卸
class Dashboard::StocktakesController < Dashboard::BaseController
  before_action :set_stocktake, only: [ :show, :count, :complete, :cancel ]
  rescue_from(Stocktake::Error) { |e| redirect_to dashboard_stocktake_path(@stocktake), alert: e.message, status: :see_other }

  def index
    @stores = current_account.stores.order(:name)
    @stocktakes = current_account.stocktakes.includes(:store, :items).order(id: :desc).page(params[:page]).per(50)
  end

  def create
    @stocktake = current_account.stocktakes.build(params.require(:stocktake).permit(:name, :store_id))
    if @stocktake.save
      redirect_to dashboard_stocktake_path(@stocktake), notice: "棚卸を開始しました。端末からも数量を登録できます。", status: :see_other
    else
      redirect_to dashboard_stocktakes_path, alert: @stocktake.errors.full_messages.join("、"), status: :see_other
    end
  end

  def show
    @items = @stocktake.items.includes(:product).to_a.sort_by { |i| -i.difference.abs }
    respond_to do |format|
      format.html
      format.csv { send_data items_csv, filename: "stocktake_#{@stocktake.id}.csv", type: "text/csv; charset=UTF-8" }
    end
  end

  def count
    product = current_account.products.find_by(code: params[:code].to_s.strip)
    raise Stocktake::Error, "商品コードが見つかりません" unless product
    raise Stocktake::Error, "数量を入力してください" unless params[:quantity].to_s.match?(/\A\d+\z/)

    @stocktake.count!(product, params[:quantity].to_i, add: params[:add] == "1")
    redirect_to dashboard_stocktake_path(@stocktake), notice: "#{product.name} を登録しました。", status: :see_other
  end

  def complete
    @stocktake.complete!(by: current_user.display_name)
    redirect_to dashboard_stocktake_path(@stocktake), notice: "棚卸を確定し、在庫数を更新しました。", status: :see_other
  end

  def cancel
    raise Stocktake::Error, "この棚卸は終了しています" unless @stocktake.counting?
    @stocktake.update!(status: :canceled)
    redirect_to dashboard_stocktakes_path, notice: "棚卸を中止しました。", status: :see_other
  end

  private

  def set_stocktake
    @stocktake = current_account.stocktakes.find(params[:id])
  end

  def items_csv
    CsvExport.generate(%w[商品コード 商品名 帳簿数 実数 差異 原価 差異金額]) do |csv|
      @items.each { |i| csv << [ i.product.code, i.product.name, i.expected, i.counted_quantity, i.difference, i.product.cost_price, i.difference_amount ] }
    end
  end
end
