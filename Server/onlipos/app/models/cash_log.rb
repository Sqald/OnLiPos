# レジの金種実査（現金の数え上げ）記録。開設・点検・途中回収・精算のタイミングで作成される。
class CashLog < ApplicationRecord
  # アソシエーション
  belongs_to :pos_token
  belongs_to :employee
  belongs_to :register_session, optional: true

  # 実査の種別。is_start/is_pickup/is_end のブール組み合わせの後継。
  # 0: open(開設), 1: check(点検), 2: pickup(旧方式の途中回収・互換用), 3: close(精算)
  enum :log_type, { open: 0, check: 1, pickup: 2, close: 3 }, prefix: :log

  # バリデーション
  validates :open_date, presence: true
  validates :yen_10000, :yen_5000, :yen_1000, :yen_500, :yen_100, :yen_50, :yen_10, :yen_5, :yen_1,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :pickup_amount, presence: true, numericality: { only_integer: true, greater_than: 0 }, if: :is_pickup?
  validate :pickup_exclusive

  # 金種構成から現金合計金額を算出する
  def total_amount
    (yen_10000 * 10000) + (yen_5000 * 5000) + (yen_1000 * 1000) +
    (yen_500 * 500) + (yen_100 * 100) + (yen_50 * 50) +
    (yen_10 * 10) + (yen_5 * 5) + (yen_1 * 1)
  end

  private

  # 途中回収レコードは開設・精算のフラグと同時に立てられないことを検証する
  def pickup_exclusive
    return unless is_pickup?
    errors.add(:base, "途中回収レコードは is_start/is_end を true にできません") if is_start? || is_end?
  end
end
