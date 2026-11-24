# 卓ごとのQRコード（お客様のスマートフォンからの注文の入口）
class TableCode < ApplicationRecord
  belongs_to :store
  before_validation { self.token ||= SecureRandom.urlsafe_base64(18) }

  validates :table_number, presence: true, uniqueness: { scope: :store_id }, length: { maximum: 16 }

  def rotate! = update!(token: SecureRandom.urlsafe_base64(18))
end
