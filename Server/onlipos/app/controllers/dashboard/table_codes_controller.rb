# セルフ注文の卓QRコードと、厨房画面・客用表示のURL
class Dashboard::TableCodesController < Dashboard::BaseController
  helper MfaHelper
  before_action :set_store, except: [ :index ]

  def index
    @stores = current_account.stores.includes(:table_codes, :pos_tokens).order(:name)
  end

  def create
    numbers = params[:table_numbers].to_s.split(/[\s,、]+/).compact_blank.uniq.first(100)
    numbers.each { |number| @store.table_codes.find_or_create_by!(table_number: number.slice(0, 16)) }
    redirect_to dashboard_table_codes_path, notice: "#{numbers.size}卓を登録しました。", status: :see_other
  end

  def rotate
    @store.table_codes.find(params[:id]).rotate!
    redirect_to dashboard_table_codes_path, notice: "QRコードを作り直しました（以前のQRコードは使えません）。", status: :see_other
  end

  def destroy
    @store.table_codes.find(params[:id]).destroy!
    redirect_to dashboard_table_codes_path, notice: "削除しました。", status: :see_other
  end

  # セルフ注文の受付の切替、厨房画面URLの再発行
  def settings
    if params[:rotate_kitchen]
      @store.rotate_kitchen_display_token!
    else
      @store.update!(self_order_enabled: params[:self_order_enabled] == "1")
    end
    redirect_to dashboard_table_codes_path, notice: "設定を変更しました。", status: :see_other
  end

  private

  def set_store
    @store = current_account.stores.find(params[:store_id])
  end
end
