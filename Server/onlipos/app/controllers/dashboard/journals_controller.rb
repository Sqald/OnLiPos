# 電子ジャーナルの閲覧・出力・改ざん検証
class Dashboard::JournalsController < Dashboard::BaseController
  TYPE_LABELS = {
    "sale" => "会計", "refund" => "返品", "register_open" => "レジ開設", "cash_check" => "レジ金チェック", "cash_pickup" => "途中回収",
    "register_close" => "レジ精算", "void" => "取消", "cash_movement" => "入出金", "receipt_issue" => "領収書発行"
  }.freeze
  helper_method :type_label

  def index
    @stores = current_account.stores.includes(:pos_tokens).order(:name)
    scope = JournalEntry.where(user: current_account).includes(:store, :pos_token, :employee)
    scope = scope.where(store_id: params[:store_id]) if params[:store_id].present?
    scope = scope.where(pos_token_id: params[:pos_token_id]) if params[:pos_token_id].present?
    scope = scope.where(entry_type: params[:type]) if JournalEntry.entry_types.key?(params[:type])
    scope = scope.where("receipt_number ILIKE ?", "%#{JournalEntry.sanitize_sql_like(params[:receipt])}") if params[:receipt].present?
    @from = parse_date(params[:from]) || Date.current
    @to = parse_date(params[:to]) || Date.current
    scope = scope.where(printed_at: @from.beginning_of_day..@to.end_of_day)

    respond_to do |format|
      format.html { @entries = scope.order(printed_at: :desc, id: :desc).page(params[:page]).per(100) }
      format.csv { send_data journals_csv(scope), filename: "journals_#{@from}_#{@to}.csv", type: "text/csv; charset=UTF-8" }
    end
  end

  def show
    @entry = JournalEntry.where(user: current_account).find(params[:id])
  end

  # 全端末のハッシュチェーンを検証する
  def verify
    @results = PosToken.joins(:store).where(stores: { user_id: current_account.id }).includes(:store).map do |pos|
      [ pos, JournalEntry.verify_chain(pos) ]
    end
  end

  private

  def journals_csv(scope)
    CsvExport.generate(%w[連番 日時 店舗 端末 種別 レシート番号 担当者 金額 内容 ハッシュ]) do |csv|
      scope.order(:id).find_each do |e|
        csv << [ e.sequence_number, e.printed_at.iso8601, e.store.name, e.pos_token.name, type_label(e.entry_type), e.receipt_number,
                 e.employee&.name, e.payload["total_amount"] || e.payload["amount"], e.payload.to_json, e.entry_hash ]
      end
    end
  end

  def type_label(type) = TYPE_LABELS.fetch(type.to_s, type)
end
