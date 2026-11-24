# 予約の確認・来店処理
class Api::V1::ReservationsController < Api::V1::BaseController
  def index
    date = params[:date].present? ? Date.iso8601(params[:date].to_s) : Date.current
    rows = @current_pos.store.reservations.where(starts_at: date.all_day).order(:starts_at)
    render json: { success: true, reservations: rows.map { |r|
      { id: r.id, name: r.name, party_size: r.party_size, table_number: r.table_number, starts_at: r.starts_at, status: r.status,
        status_label: Reservation::STATUS_LABELS[r.status], note: r.note }
    } }
  rescue Date::Error
    render json: { success: false, message: "日付の形式が不正です" }, status: :bad_request
  end

  def update
    reservation = @current_pos.store.reservations.find(params[:id])
    unless Reservation.statuses.key?(params[:status])
      return render json: { success: false, message: "状態が不正です" }, status: :unprocessable_entity
    end

    reservation.status = params[:status]
    if reservation.save
      render json: { success: true, status: reservation.status }
    else
      render json: { success: false, message: reservation.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end
end
