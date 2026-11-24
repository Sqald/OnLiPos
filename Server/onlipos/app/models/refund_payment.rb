# 返金の決済手段別内訳（現金でいくら、カードの取消でいくら返したか）
class RefundPayment < ApplicationRecord
  belongs_to :refund

  # SalePayment と同じ番号を使う
  enum :method, PaymentMethods::VALUES

  validates :amount, presence: true, numericality: { only_integer: true, greater_than: 0 }
end
