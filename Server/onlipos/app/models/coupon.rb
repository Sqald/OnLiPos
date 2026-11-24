# クーポン。会計の小計から割り引く
class Coupon < ApplicationRecord
  include Auditable
  class Unusable < StandardError; end

  belongs_to :user
  enum :discount_type, { amount: 0, percent: 1 }, prefix: :discount

  normalizes :code, with: ->(code) { code.strip.upcase }
  validates :code, presence: true, uniqueness: { scope: :user_id }, format: { with: /\A[A-Z0-9-]{3,32}\z/ }
  validates :name, presence: true
  validates :discount_value, numericality: { only_integer: true, greater_than: 0 }
  validates :discount_value, numericality: { less_than_or_equal_to: 100 }, if: :discount_percent?
  validates :min_total, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # 使えない理由（使えるなら nil）
  def unusable_reason(total, date = Date.current)
    return "このクーポンは無効です" unless active
    return "クーポンの利用期間外です" if (starts_on && date < starts_on) || (ends_on && date > ends_on)
    return "クーポンの利用上限に達しています" if usage_limit && used_count >= usage_limit

    "このクーポンは#{min_total}円以上の会計で利用できます" if total < min_total
  end

  def discount_for(total)
    discount_percent? ? total * discount_value / 100 : [ discount_value, total ].min
  end

  # 利用を確定する（上限の判定を含めて行ロックで行う）
  def redeem!(total, date = Date.current)
    with_lock do
      reason = unusable_reason(total, date)
      raise Unusable, reason if reason

      update_columns(used_count: used_count + 1)
    end
  end

  def release! = self.class.where(id: id).where("used_count > 0").update_all("used_count = used_count - 1")
end
