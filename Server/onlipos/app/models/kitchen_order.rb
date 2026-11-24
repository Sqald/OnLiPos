# 厨房への注文。items: [{ "product_id", "name", "quantity", "options": ["..."], "note" }]
class KitchenOrder < ApplicationRecord
  belongs_to :store

  enum :source, { pos: 0, self_order: 1 }
  enum :status, { waiting: 0, accepted: 1, served: 2, canceled: 3 }
  STATUS_LABELS = { "waiting" => "受付待ち", "accepted" => "調理中", "served" => "提供済み", "canceled" => "取消" }.freeze

  validate { errors.add(:items, "がありません") unless items.is_a?(Array) && items.any? }

  scope :in_progress, -> { where(status: %i[waiting accepted]).order(:created_at) }

  def advance!
    waiting? ? update!(status: :accepted, accepted_at: Time.current) : update!(status: :served, served_at: Time.current)
  end
end
