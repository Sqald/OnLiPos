class Employee < ApplicationRecord
  MAX_FAILED_ATTEMPTS = 10
  UNLOCK_IN = 1.hour

  belongs_to :user
  has_secure_password :pin, validations: false
  has_and_belongs_to_many :stores

  validates :code, presence: true, uniqueness: { scope: :user_id }, length: { in: 1..12 }
  validates :pin, format: { with: /\A\d{4,6}\z/ }, allow_nil: true

  # アカウントが現在ロックされているか確認
  def access_locked?
    locked_at.present? && locked_at > UNLOCK_IN.ago
  end

  # ログイン成功時に呼び出し、ロック状態をリセット
  def unlock_access!
    self.update_columns(failed_attempts: 0, locked_at: nil, updated_at: Time.current)
  end

  # ログイン失敗時に呼び出し、失敗回数をインクリメント
  def increment_failed_attempts
    self.increment!(:failed_attempts)
    # 閾値を超えたらアカウントをロック
    if failed_attempts >= MAX_FAILED_ATTEMPTS && !access_locked?
      self.update_column(:locked_at, Time.current)
    end
  end
end
