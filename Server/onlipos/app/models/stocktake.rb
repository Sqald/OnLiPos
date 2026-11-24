# 棚卸。数えた数量を記録し、確定すると在庫数を実数に合わせる
class Stocktake < ApplicationRecord
  include Auditable
  class Error < StandardError; end

  belongs_to :user
  belongs_to :store
  has_many :items, class_name: "StocktakeItem", dependent: :destroy

  enum :status, { counting: 0, completed: 1, canceled: 2 }
  STATUS_LABELS = { "counting" => "実施中", "completed" => "確定", "canceled" => "中止" }.freeze

  validates :name, presence: true
  validate { errors.add(:store, "が不正です") if store && store.user_id != user_id }

  # 数量を記録する。add: true なら加算（複数箇所に分けて数える場合）
  def count!(product, quantity, employee: nil, add: false)
    raise Error, "この棚卸は終了しています" unless counting?
    raise Error, "数量は0以上を指定してください" if quantity.negative?

    with_lock do
      item = items.find_or_initialize_by(product: product)
      item.update!(counted_quantity: add ? item.counted_quantity.to_i + quantity : quantity, employee: employee)
      item
    end
  end

  def complete!(by:)
    with_lock do
      raise Error, "この棚卸は終了しています" unless counting?

      items.includes(:product).each do |item|
        stock = StoreStock.find_or_create_by!(store: store, product: item.product)
        stock.with_lock do
          item.update!(expected_quantity: stock.quantity)
          StoreStock.adjust!(store: store, product: item.product, change: item.difference, reason: "stocktake", employee: item.employee)
        end
      end
      update!(status: :completed, completed_at: Time.current, completed_by_name: by)
    end
  end
end
