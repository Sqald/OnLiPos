class Refund < ApplicationRecord
  belongs_to :sale
  belongs_to :store
  belongs_to :user
  belongs_to :pos_token, optional: true
  has_many :refund_details, dependent: :destroy

  validates :total_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }

  before_validation :set_refund_receipt_number, on: :create

  private

  def set_refund_receipt_number
    return if refund_receipt_number.present?
    prefix = "REFUND-#{sale&.receipt_number}-"
    self.refund_receipt_number = "#{prefix}#{Time.current.to_i}"
  end
end
