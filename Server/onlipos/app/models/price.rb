# 店舗別の商品価格（Product のデフォルト価格を店舗ごとに上書きする）
class Price < ApplicationRecord
  belongs_to :store
  belongs_to :product

  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
