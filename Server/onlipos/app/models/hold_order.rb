class HoldOrder < ApplicationRecord
  belongs_to :store

  validates :operator_name, presence: true
  validates :operator_id, presence: true
  validates :total_amount, presence: true
end
