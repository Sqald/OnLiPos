# 仕入先
class Supplier < ApplicationRecord
  include Auditable
  belongs_to :user
  has_many :purchase_orders, dependent: :restrict_with_error
  has_many :products, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :invoice_registration_number, format: { with: /\AT\d{13}\z/, message: "はT+数字13桁で入力してください" }, allow_blank: true
end
