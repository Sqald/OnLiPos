# 勤怠（出勤・退勤・休憩）。POS端末でのPIN認証で打刻する
class Attendance < ApplicationRecord
  class Error < StandardError; end

  belongs_to :employee
  belongs_to :store
  belongs_to :pos_token, optional: true

  validates :clock_in_at, presence: true
  validates :break_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate { errors.add(:clock_out_at, "は出勤より後にしてください") if clock_out_at && clock_in_at && clock_out_at < clock_in_at }

  scope :open, -> { where(clock_out_at: nil) }

  ACTIONS = %w[clock_in clock_out break_start break_end].freeze

  def self.punch!(action, employee:, store:, pos_token:)
    current = open.find_by(employee: employee)
    case action
    when "clock_in"
      raise Error, "すでに出勤済みです" if current
      create!(employee: employee, store: store, pos_token: pos_token, clock_in_at: Time.current)
    when "clock_out"
      raise Error, "出勤していません" unless current
      current.end_break! if current.break_started_at
      current.update!(clock_out_at: Time.current)
      current
    when "break_start"
      raise Error, "出勤していないか、すでに休憩中です" if current.nil? || current.break_started_at
      current.update!(break_started_at: Time.current)
      current
    when "break_end"
      raise Error, "休憩中ではありません" unless current&.break_started_at
      current.end_break!
      current
    else
      raise Error, "不明な操作です"
    end
  rescue ActiveRecord::RecordNotUnique
    raise Error, "すでに出勤済みです"
  end

  def end_break!
    minutes = ((Time.current - break_started_at) / 60).floor
    update!(break_minutes: break_minutes + minutes, break_started_at: nil)
  end

  def worked_minutes
    return nil unless clock_out_at

    [ ((clock_out_at - clock_in_at) / 60).floor - break_minutes, 0 ].max
  end
end
