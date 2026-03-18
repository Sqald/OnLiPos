class Store < ApplicationRecord
  belongs_to :user
  has_many :pos_tokens, dependent: :destroy
  has_many :prices, dependent: :destroy
  has_many :store_stocks, dependent: :destroy
  has_many :sales, dependent: :destroy
  has_many :stocked_products, through: :store_stocks, source: :product
  has_and_belongs_to_many :employees

  delegate :products, to: :user

  validates :name, presence: true, uniqueness: true
  validates :ascii_name, presence: true, length: { in: 3..16 }, format: { with: /\A[a-zA-Z0-9]+\z/ }, uniqueness: { scope: :user_id, case_sensitive: false }

  after_create :assign_employees_marked_as_all_stores

  private

  def assign_employees_marked_as_all_stores
    Employee.joins(:stores).where(stores: { user_id: user_id }).where(is_all_stores: true).distinct.each do |employee|
      employee.stores << self unless employee.stores.exists?(id)
    end
  end
end
