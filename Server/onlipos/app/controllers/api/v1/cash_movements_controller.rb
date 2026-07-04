# レジ現金の入出金（釣銭補充・雑入金・雑出金・途中回収）。
# 金種実査（cash_logs）とは別に「現金の移動」を記録し、理論在高に反映する。
# 権限は途中回収と同じ cash_pickup を使う（レジ現金を動かす操作として同格）。
class Api::V1::CashMovementsController < Api::V1::BaseController
  # GET /api/v1/cash_movements — 現在のセッション（なければ当日）の入出金一覧
  def index
    session = current_open_session
    scope =
      if session
        session.cash_movements
      else
        @current_pos.cash_movements.where(occurred_at: Date.current.all_day)
      end

    movements = scope.order(occurred_at: :desc).limit(100)

    render json: {
      success: true,
      movements: movements.map { |m|
        {
          id: m.id,
          kind: m.kind,
          direction: m.direction,
          amount: m.amount,
          reason: m.reason,
          occurred_at: m.occurred_at
        }
      }
    }, status: :ok
  end

  # POST /api/v1/cash_movements
  def create
    owner = @current_pos.store.user
    employee = owner.employees.find_by(id: movement_params[:employee_id])

    unless employee && (employee.is_all_stores || employee.stores.exists?(@current_pos.store.id))
      return render json: { success: false, message: "担当者が見つかりません" }, status: :forbidden
    end

    unless employee.permitted?("cash_pickup")
      return render json: { success: false, message: "レジ入出金の権限がありません" }, status: :forbidden
    end

    kind = normalize_kind(movement_params[:kind])
    unless kind
      return render json: { success: false, message: "入出金種別が不正です" }, status: :unprocessable_entity
    end

    amount = movement_params[:amount].to_i
    if amount <= 0
      return render json: { success: false, message: "金額は1円以上を指定してください" }, status: :unprocessable_entity
    end

    movement = CashMovement.new(
      store: @current_pos.store,
      pos_token: @current_pos,
      register_session: current_open_session,
      employee: employee,
      kind: kind,
      direction: CashMovement.direction_for(kind),
      amount: amount,
      reason: movement_params[:reason],
      occurred_at: Time.current
    )

    ActiveRecord::Base.transaction do
      movement.save!
      JournalEntry.create_from_cash_movement!(movement)
    end

    render json: {
      success: true,
      movement_id: movement.id,
      kind: movement.kind,
      direction: movement.direction,
      amount: movement.amount,
      reason: movement.reason,
      occurred_at: movement.occurred_at
    }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, message: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
  end

  private

  def movement_params
    params.permit(:employee_id, :kind, :amount, :reason)
  end

  def current_open_session
    return @current_open_session if defined?(@current_open_session)
    @current_open_session = @current_pos.register_sessions.open.first
  end

  # kind は enum 名（"replenishment" 等）と数値コードの両方を受け付ける
  def normalize_kind(value)
    return nil if value.blank?
    name = value.to_s
    return name if CashMovement.kinds.key?(name)
    if name.match?(/\A\d+\z/)
      CashMovement.kinds.key(name.to_i)
    end
  end
end
