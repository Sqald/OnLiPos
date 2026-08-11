# 在庫変動の監査ログ（StoreStock の増減を1件ずつ記録し、変動理由・関連する売上を紐付ける）
class StockMovement < ApplicationRecord
  belongs_to :store
  belongs_to :product
  belongs_to :store_stock
  belongs_to :sale, optional: true
  belongs_to :employee, optional: true
  belongs_to :pos_token, optional: true

  validates :quantity_change, presence: true
  validates :reason, presence: true
end
