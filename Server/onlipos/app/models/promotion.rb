# 自動値引き
#   time_sale   : 対象商品を percent_off % 引き、または fixed_price 円で販売（1点ごと）
#   set_price   : 対象商品を合わせて set_quantity 点で fixed_price 円（よりどり）
#   set_percent : 対象商品を合わせて set_quantity 点以上で percent_off % 引き
class Promotion < ApplicationRecord
  include Auditable
  belongs_to :user
  belongs_to :product_category, optional: true
  has_and_belongs_to_many :products

  enum :kind, { time_sale: 0, set_price: 1, set_percent: 2 }
  KIND_LABELS = { "time_sale" => "タイムセール", "set_price" => "よりどり定額", "set_percent" => "まとめ買い割引" }.freeze

  validates :name, presence: true
  validates :percent_off, numericality: { only_integer: true, in: 1..100 }, allow_nil: true
  validates :fixed_price, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :set_quantity, numericality: { only_integer: true, greater_than: 1 }, unless: :time_sale?
  validates :start_minute, :end_minute, numericality: { only_integer: true, in: 0..1440 }, allow_nil: true
  validate :terms_match_kind
  validate :targets_belong_to_account

  def active_at?(time)
    local = time.in_time_zone
    date = local.to_date
    minute = local.hour * 60 + local.min
    active &&
      (starts_on.nil? || date >= starts_on) && (ends_on.nil? || date <= ends_on) &&
      (weekdays.empty? || weekdays.include?(date.wday)) &&
      (start_minute.nil? || minute >= start_minute) && (end_minute.nil? || minute < end_minute)
  end

  def targets?(product)
    (product_category_id && product.product_category_id == product_category_id) || product_ids.include?(product.id)
  end

  # タイムセールの販売単価（通常単価より高くはしない）
  def sale_price(base_price)
    [ fixed_price || base_price * (100 - percent_off) / 100, base_price ].min
  end

  # まとめ買いの割引額。units は対象の単価（1点ずつ）の配列
  def set_discount(units)
    units = units.sort.reverse
    return 0 if units.size < set_quantity

    if set_percent?
      units.sum * percent_off / 100
    else
      count = units.size / set_quantity * set_quantity
      [ units.first(count).sum - count / set_quantity * fixed_price, 0 ].max
    end
  end

  # 画面入力用（HH:MM）
  def start_time = format_minute(start_minute)
  def end_time = format_minute(end_minute)
  def start_time=(value)
    self.start_minute = parse_minute(value)
  end
  def end_time=(value)
    self.end_minute = parse_minute(value)
  end

  private

  def format_minute(minute) = minute && format("%02d:%02d", minute / 60, minute % 60)

  def parse_minute(value)
    match = value.to_s.match(/\A(\d{1,2}):(\d{2})\z/)
    match && match[1].to_i * 60 + match[2].to_i
  end

  def terms_match_kind
    errors.add(:base, "割引率か販売価格のどちらかを指定してください") if time_sale? && percent_off.nil? == fixed_price.nil?
    errors.add(:fixed_price, "を指定してください") if set_price? && fixed_price.nil?
    errors.add(:percent_off, "を指定してください") if set_percent? && percent_off.nil?
    errors.add(:base, "対象の商品またはカテゴリを指定してください") if product_category_id.nil? && product_ids.empty?
  end

  def targets_belong_to_account
    errors.add(:product_category, "が不正です") if product_category && product_category.user_id != user_id
    errors.add(:products, "が不正です") if products.any? { |p| p.user_id != user_id }
  end
end
