class Dashboard::CashLogsController < Dashboard::BaseController
  # レジ金履歴は検索条件（店舗・端末・日付・種別）を指定して検索したときのみデータを取得する。
  # 自ユーザー配下の店舗・POS端末のログのみに厳格にスコープする。
  def index
    @stores = current_user.stores.includes(:pos_tokens).order(:name)
    @allowed_store_ids = current_user.stores.pluck(:id)
    @allowed_pos_token_ids = PosToken.joins(:store).where(stores: { user_id: current_user.id }).pluck(:id)

    unless search_performed?
      @cash_logs = CashLog.none.page(1).per(50)
      return
    end

    scope = CashLog
      .joins(pos_token: :store)
      .where(stores: { user_id: current_user.id })

    if params[:store_id].present? && @allowed_store_ids.include?(params[:store_id].to_i)
      scope = scope.where(pos_tokens: { store_id: params[:store_id] })
    end

    if params[:pos_token_id].present? && @allowed_pos_token_ids.include?(params[:pos_token_id].to_i)
      scope = scope.where(pos_token_id: params[:pos_token_id])
    end

    if params[:from].present?
      from_date = Date.strptime(params[:from], '%Y-%m-%d') rescue nil
      scope = scope.where("open_date >= ?", from_date) if from_date
    end

    if params[:to].present?
      to_date = Date.strptime(params[:to], '%Y-%m-%d') rescue nil
      scope = scope.where("open_date <= ?", to_date) if to_date
    end

    if params[:kind].present?
      case params[:kind]
      when "open"
        scope = scope.where(is_start: true)
      when "check"
        scope = scope.where(is_start: false, is_end: false)
      when "close"
        scope = scope.where(is_end: true)
      end
    end

    @cash_logs = scope
      .includes(:employee, pos_token: :store)
      .order(open_date: :desc, created_at: :desc)
      .page(params[:page])
      .per(50)
  end

  private

  def search_performed?
    params[:store_id].present? ||
      params[:pos_token_id].present? ||
      params[:from].present? ||
      params[:to].present? ||
      params[:kind].present?
  end
end
