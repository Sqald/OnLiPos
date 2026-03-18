class Saledetail < ApplicationRecord
  belongs_to :sale
  belongs_to :product
  has_many :refund_details, dependent: :restrict_with_exception
end
