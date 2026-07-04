# レジ現金の入出金（釣銭補充・雑入出金・途中回収）。
# 金種実査（cash_logs）とは別に「現金の移動」という事実を記録し、
# 理論在高 = 釣銭準備金 + 現金売上 − 現金返金 + 入金 − 出金 の照合に使う。
class CashMovement < ApplicationRecord
  belongs_to :store
  belongs_to :pos_token
  belongs_to :register_session, optional: true
  belongs_to :employee

  enum :kind, { pickup: 0, replenishment: 1, misc_in: 2, misc_out: 3 }
  enum :direction, { inbound: 0, outbound: 1 }

  validates :amount, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :occurred_at, presence: true
  validate :direction_matches_kind

  KIND_DIRECTIONS = {
    "pickup"        => "outbound",
    "replenishment" => "inbound",
    "misc_in"       => "inbound",
    "misc_out"      => "outbound"
  }.freeze

  # 種別に対応する方向を返す（API層での自動設定用）
  def self.direction_for(kind)
    KIND_DIRECTIONS.fetch(kind.to_s)
  end

  private

  def direction_matches_kind
    return if kind.blank? || direction.blank?
    expected = KIND_DIRECTIONS[kind]
    errors.add(:direction, "が入出金種別と一致しません") if expected && direction != expected
  end
end
