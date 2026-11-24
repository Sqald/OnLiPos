# 予約
class Reservation < ApplicationRecord
  belongs_to :store
  belongs_to :customer, optional: true

  enum :status, { booked: 0, seated: 1, finished: 2, canceled: 3, no_show: 4 }
  STATUS_LABELS = { "booked" => "予約", "seated" => "来店", "finished" => "終了", "canceled" => "取消", "no_show" => "来店なし" }.freeze

  validates :name, :starts_at, presence: true
  validates :party_size, numericality: { only_integer: true, greater_than: 0 }
  validate { errors.add(:ends_at, "は開始より後にしてください") if ends_at && starts_at && ends_at <= starts_at }
  validate :table_available, if: -> { table_number.present? && (booked? || seated?) }

  def effective_end = ends_at || (starts_at + 2.hours)

  private

  # 同じ卓の予約が重ならないこと
  def table_available
    overlapping = Reservation.where(store_id: store_id, table_number: table_number, status: %i[booked seated]).where.not(id: id)
                             .where("starts_at < ? AND COALESCE(ends_at, starts_at + INTERVAL '2 hours') > ?", effective_end, starts_at)
    errors.add(:table_number, "は同じ時間帯に予約があります") if starts_at && overlapping.exists?
  end
end
