# POS端末の初期設定プロファイル（初回導入時の店舗コンテキスト・ハードウェア設定をまとめたもの）。
# provisioning API 経由で端末に配布され、PosToken から参照される。
class Provisioning < ApplicationRecord
  belongs_to :user
  belongs_to :store
  has_many :pos_tokens, dependent: :nullify

  validates :name, presence: true
  validates :store_context, presence: true
  validates :hardware_settings, presence: true
end
