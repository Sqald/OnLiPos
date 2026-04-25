class TableOrder < ApplicationRecord
  belongs_to :store

  validates :table_number, presence: true
  validates :table_number, uniqueness: { scope: :store_id }
end
