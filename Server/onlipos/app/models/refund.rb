class Refund < ApplicationRecord
  belongs_to :sale
  belongs_to :store
  belongs_to :user
  belongs_to :pos_token, optional: true
  belongs_to :employee, optional: true
  belongs_to :register_session, optional: true
  has_many :refund_details, dependent: :destroy
  has_many :refund_tax_breakdowns, dependent: :destroy

  validates :total_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }

  before_validation :set_refund_receipt_number, on: :create
  before_validation :set_accounting_dates, on: :create

  private

  # 集計はすべて business_date（営業日）基準のため、どの経路で作成されても必ず値を持たせる
  def set_accounting_dates
    self.refunded_at ||= Time.current
    self.business_date ||= refunded_at.in_time_zone.to_date
  end

  def set_refund_receipt_number
    return if refund_receipt_number.present?
    prefix = "REFUND-#{sale&.receipt_number}-"
    self.refund_receipt_number = "#{prefix}#{Time.current.to_i}"
  end
end
