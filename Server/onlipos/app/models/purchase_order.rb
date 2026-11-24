# 発注。入荷すると在庫が増え、商品の原価（最終仕入原価）が更新される
class PurchaseOrder < ApplicationRecord
  include Auditable
  class Error < StandardError; end

  belongs_to :user
  belongs_to :store
  belongs_to :supplier
  has_many :items, class_name: "PurchaseOrderItem", dependent: :destroy, inverse_of: :purchase_order
  accepts_nested_attributes_for :items, allow_destroy: true, reject_if: ->(attrs) { attrs["product_id"].blank? || attrs["quantity"].to_i <= 0 }

  enum :status, { draft: 0, ordered: 1, partially_received: 2, received: 3, canceled: 4 }
  STATUS_LABELS = { "draft" => "下書き", "ordered" => "発注済み", "partially_received" => "一部入荷", "received" => "入荷済み", "canceled" => "取消" }.freeze

  before_validation :assign_number, on: :create
  validates :number, presence: true, uniqueness: { scope: :user_id }
  validate { errors.add(:base, "商品を1つ以上指定してください") if items.reject(&:marked_for_destruction?).empty? }
  validate { errors.add(:store, "が不正です") if store && store.user_id != user_id }
  validate { errors.add(:supplier, "が不正です") if supplier && supplier.user_id != user_id }

  def audit_name = number
  def total_amount = items.sum { |i| i.quantity * i.unit_cost }
  def receivable? = ordered? || partially_received?

  def place!
    raise Error, "下書きの発注のみ確定できます" unless draft?
    update!(status: :ordered, ordered_on: Date.current)
  end

  def cancel!
    raise Error, "入荷済みの発注は取り消せません" unless draft? || ordered?
    update!(status: :canceled)
  end

  # quantities: { 明細ID => 入荷数 }
  def receive!(quantities, employee: nil, pos_token: nil)
    with_lock do
      raise Error, "入荷できない状態の発注です" unless receivable?

      received_any = false
      items.includes(:product).each do |item|
        quantity = quantities[item.id.to_s].to_i
        next if quantity.zero?
        raise Error, "入荷数が不正です: #{item.product.name}" if quantity.negative? || quantity > item.remaining

        item.update!(received_quantity: item.received_quantity + quantity)
        StoreStock.adjust!(store: store, product: item.product, change: quantity, reason: "purchase", employee: employee, pos_token: pos_token)
        item.product.update!(cost_price: item.unit_cost) if item.unit_cost.positive? && item.product.cost_price != item.unit_cost
        received_any = true
      end
      raise Error, "入荷数を入力してください" unless received_any

      update!(status: items.reload.all? { |i| i.remaining.zero? } ? :received : :partially_received)
    end
  end

  private

  def assign_number
    self.number ||= "PO#{Date.current.strftime('%Y%m%d')}-#{SecureRandom.alphanumeric(5).upcase}"
  end
end
