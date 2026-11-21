# ダッシュボードログインの2段階目に使うパスキー（WebAuthn 資格情報）。
# 公開鍵と署名カウンタのみを保存し、秘密鍵は利用者の端末（パスワードマネージャー等）から出ない。
class UserPasskey < ApplicationRecord
  belongs_to :user

  validates :external_id, presence: true, uniqueness: true
  validates :public_key, presence: true
  validates :nickname, presence: true, length: { maximum: 50 }
end
