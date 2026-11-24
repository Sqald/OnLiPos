# 店舗ごとの商品在庫数。増減の履歴は StockMovement に記録される
class StoreStock < ApplicationRecord
  belongs_to :store
  belongs_to :product
  has_many :stock_movements, dependent: :destroy

  validates :quantity, numericality: { only_integer: true }

  # 在庫を増減し、履歴を残す。在庫を管理しない商品では何もしない
  def self.adjust!(store:, product:, change:, reason:, employee: nil, pos_token: nil, sale: nil)
    return if change.zero? || !product.track_stock

    stock = find_or_create_by!(store: store, product: product)
    stock.with_lock do
      before = stock.quantity
      stock.update!(quantity: before + change)
      StockMovement.create!(store: store, product: product, store_stock: stock, employee: employee, pos_token: pos_token, sale: sale,
                            quantity_change: change, reason: reason)
      stock.notify_low_stock(before)
    end
    stock
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def low? = product.low_stock_threshold.present? && quantity <= product.low_stock_threshold

  # しきい値を下回った瞬間だけ通知する
  def notify_low_stock(before)
    threshold = product.low_stock_threshold
    return if threshold.nil? || before <= threshold || quantity > threshold

    Webhook.publish(store.user, "stock.low", { store_id: store_id, store_name: store.name, product_id: product_id, product_code: product.code,
                                                product_name: product.name, quantity: quantity, threshold: threshold })
  end
end
