# 適用日を指定した価格・税率の変更。適用日の0時（日本時間）以降、最初の定期処理またはAPIアクセス時に反映する。
# 端末にも配布し、オフラインでも適用日から新しい価格・税率で会計できるようにする。
class ScheduledProductChange < ApplicationRecord
  belongs_to :user
  belongs_to :product
  belongs_to :store, optional: true

  PRODUCT_FIELDS = %w[price tax_rate tax_type eat_in_price eat_in_tax_rate].freeze

  enum :tax_type, { inclusive: 0, exclusive: 1, tax_free: 2 }, prefix: :tax

  validates :effective_on, presence: true
  validates :price, :tax_rate, :eat_in_price, :eat_in_tax_rate,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :tax_rate, :eat_in_tax_rate, numericality: { less_than_or_equal_to: 100 }, allow_nil: true
  validate :must_change_something
  validate :must_belong_to_same_account

  scope :pending, -> { where(applied_at: nil) }
  scope :due, ->(date = Date.current) { pending.where(effective_on: ..date) }

  # 適用日が来た変更を反映する。account を省略すると全契約が対象
  def self.apply_due!(account = nil)
    scope = due
    scope = scope.where(user: account) if account
    return 0 unless scope.exists?

    scope.includes(:product, :store).order(:effective_on, :id).to_a.count(&:apply!)
  end

  def apply!
    with_lock do
      return false if applied_at

      effective_at = effective_on.in_time_zone.beginning_of_day
      if store
        apply_store_price
      else
        product.effective_at = effective_at
        product.update!(attributes.slice(*PRODUCT_FIELDS).compact)
      end
      update!(applied_at: Time.current)
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[ScheduledProductChange] ##{id} #{e.message}"
    false
  end

  def changes_summary
    [ ("価格 #{price}円" if price), ("税率 #{tax_rate}%" if tax_rate), ("店内価格 #{eat_in_price}円" if eat_in_price),
      ("店内税率 #{eat_in_tax_rate}%" if eat_in_tax_rate), (Product.tax_type_label(tax_type) if tax_type) ].compact.join("、")
  end

  private

  def apply_store_price
    row = Price.find_or_initialize_by(store: store, product: product)
    row.update!(amount: price) if price
  end

  def must_change_something
    errors.add(:base, "変更する項目を指定してください") if attributes.slice(*PRODUCT_FIELDS).values.compact.empty?
    errors.add(:base, "店舗別の予約では価格だけを変更できます") if store && (attributes.slice(*PRODUCT_FIELDS).compact.keys - [ "price" ]).any?
  end

  def must_belong_to_same_account
    errors.add(:product, "が不正です") if product && product.user_id != user_id
    errors.add(:store, "が不正です") if store && store.user_id != user_id
  end
end
