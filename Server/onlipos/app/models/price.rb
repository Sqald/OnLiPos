# 店舗別の商品価格（Product のデフォルト価格を店舗ごとに上書きする）
class Price < ApplicationRecord
  include Auditable

  def audit_name = "#{product&.name}（#{store&.name}）"
  belongs_to :store
  belongs_to :product

  # 変更・削除前の店舗価格を履歴に残す。あわせて商品の更新日時を進め、差分同期で端末へ届くようにする
  before_update :record_history, if: :amount_changed?
  before_destroy :record_history
  after_commit :touch_product

  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }

  private

  def record_history
    ProductPriceHistory.create!(product_id: product_id, store_id: store_id, price: amount_was || amount, replaced_at: Time.current)
  end

  def touch_product
    Product.where(id: product_id).update_all(updated_at: Time.current)
  end
end
