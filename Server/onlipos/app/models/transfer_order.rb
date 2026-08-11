# 店舗間の商品移動オーダー
class TransferOrder < ApplicationRecord
  belongs_to :store

  validates :operator_name, presence: true
  validates :operator_id,   presence: true
  validates :total_amount,  numericality: { greater_than_or_equal_to: 0 }
end
