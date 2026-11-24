# 会計ソフト用の仕訳データ出力（日次・店舗別）
class Dashboard::AccountingExportsController < Dashboard::BaseController
  def show
    @stores = current_account.stores.order(:name)
    @from = parse_date(params[:from]) || Date.current.prev_month.beginning_of_month
    @to = parse_date(params[:to]) || Date.current.prev_month.end_of_month
    return if params[:export].blank?

    export = AccountingExport.new(current_account, from: @from, to: @to, store_ids: @stores.where(id: params[:store_id].presence || @stores.ids).ids)
    AuditLog.record("export", details: { "操作" => "仕訳データの出力", "期間" => "#{@from} 〜 #{@to}", "形式" => params[:export] })
    data, filename = export.to_file(params[:export])
    send_data data, filename: filename, type: "text/csv"
  end
end
