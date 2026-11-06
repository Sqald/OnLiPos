# 電子ジャーナル（売上・返品・レジ開閉・入出金等の全取引記録）の閲覧API。
# view_journal 権限を持つ従業員のみ閲覧可能。POS端末・日付・種別で絞り込みできる。
class Api::V1::JournalsController < Api::V1::BaseController
  # GET /api/v1/journals?pos_id=&date=&type=&employee_id=
  # 条件に合致するジャーナルエントリを新しい順に最大200件返す
  def index
    store    = @current_pos.store
    employee = require_store_employee!(params[:employee_id])
    return unless employee

    authorize_employee!(employee, "view_journal")
    return if performed?

    scope = store.journal_entries.includes(:employee, :pos_token)
    scope = filter_scope(scope)

    entries = scope.order(printed_at: :desc).limit(200)

    render json: {
      success: true,
      entries: entries.map { |e| entry_summary(e) }
    }
  rescue ArgumentError
    render json: { success: false, message: "日付の形式が不正です" }, status: :bad_request
  end

  # GET /api/v1/journals/:id
  # ジャーナルエントリ1件の詳細（payload含む）を返す
  def show
    store    = @current_pos.store
    employee = require_store_employee!(params[:employee_id])
    return unless employee

    authorize_employee!(employee, "view_journal")
    return if performed?

    entry = store.journal_entries.find(params[:id])
    render json: { success: true, entry: entry_detail(entry) }
  end

  private

  # pos_id / date / type パラメータでジャーナルエントリを絞り込む
  def filter_scope(scope)
    if params[:pos_id].present?
      pos = @current_pos.store.pos_tokens.find_by(id: params[:pos_id])
      scope = scope.where(pos_token: pos) if pos
    end

    if params[:date].present?
      date  = Date.parse(params[:date])
      scope = scope.where(printed_at: date.all_day)
    end

    if params[:type].present?
      scope = scope.where(entry_type: params[:type])
    end

    scope
  end

  # 一覧表示用のサマリー（一覧・詳細で共通のフィールドをまとめる）
  def entry_summary(e)
    {
      id:             e.id,
      entry_type:     e.entry_type,
      receipt_number: e.receipt_number,
      printed_at:     e.printed_at,
      pos_name:       e.pos_token.name,
      employee_name:  e.employee&.name,
      amount:         e.payload["total_amount"] || e.payload["pickup_amount"]
    }
  end

  # 詳細表示用（サマリーに payload 全体を加えたもの）
  def entry_detail(e)
    entry_summary(e).merge(payload: e.payload)
  end
end
