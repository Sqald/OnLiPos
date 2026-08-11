# 電子ジャーナル（売上・返品・レジ開閉・入出金等の全取引記録）の閲覧API。
# view_journal 権限を持つ従業員のみ閲覧可能。POS端末・日付・種別で絞り込みできる。
class Api::V1::JournalsController < Api::V1::BaseController
  include EmployeePermissionAuthorizable

  # GET /api/v1/journals?pos_id=&date=&type=&employee_id=
  # 条件に合致するジャーナルエントリを新しい順に最大200件返す
  def index
    store    = @current_pos.store
    employee = resolve_employee!(store)
    return if performed?

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
    employee = resolve_employee!(store)
    return if performed?

    authorize_employee!(employee, "view_journal")
    return if performed?

    entry = store.journal_entries.find(params[:id])
    render json: { success: true, entry: entry_detail(entry) }
  end

  private

  # employee_id から担当者を特定し、店舗権限（全店舗権限 or 所属店舗）を確認する。
  # 不正な場合は 403 を描画する（呼び出し側は performed? で中断を検知）。
  def resolve_employee!(store)
    employee = store.user.employees.find_by(id: params[:employee_id])
    unless employee && (employee.is_all_stores || employee.stores.exists?(store.id))
      render json: { success: false, message: "担当者が見つからないか、店舗の権限がありません" },
             status: :forbidden
    end
    employee
  end

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
