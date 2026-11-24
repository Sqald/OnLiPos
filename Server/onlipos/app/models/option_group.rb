# 商品のオプション（トッピング・サイズなど）のグループ
class OptionGroup < ApplicationRecord
  include Auditable
  belongs_to :user
  has_many :option_items, -> { order(:position, :id) }, dependent: :destroy
  has_and_belongs_to_many :products
  accepts_nested_attributes_for :option_items, allow_destroy: true, reject_if: ->(attrs) { attrs["name"].blank? }

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :min_select, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :max_select, numericality: { only_integer: true, greater_than: 0 }
  validate { errors.add(:max_select, "は最小数以上にしてください") if max_select.to_i < min_select.to_i }

  after_commit { Product.where(id: product_ids).update_all(updated_at: Time.current) unless destroyed? }
end
