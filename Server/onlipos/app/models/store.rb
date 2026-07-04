class Store < ApplicationRecord
  belongs_to :user
  has_many :pos_tokens, dependent: :destroy
  has_many :prices, dependent: :destroy
  has_many :store_stocks, dependent: :destroy
  has_many :sales, dependent: :destroy
  has_many :stocked_products, through: :store_stocks, source: :product
  has_many :table_orders, dependent: :destroy
  has_many :hold_orders, dependent: :destroy
  has_many :transfer_orders, dependent: :destroy
  # ジャーナルは readonly（追記型）のため destroy ではなく delete_all で削除する
  has_many :journal_entries, dependent: :delete_all
  has_many :register_sessions, dependent: :destroy
  has_many :cash_movements, dependent: :destroy
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
