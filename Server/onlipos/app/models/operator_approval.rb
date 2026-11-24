# 担当者のPIN認証結果（承認）。PIN認証に成功すると発行され、以後の操作APIは
# このトークンを X-Operator-Approval ヘッダーで提示する。
# DBにはダイジェストだけを保存し、平文は発行時の応答でのみ返す。
class OperatorApproval < ApplicationRecord
  belongs_to :employee
  belongs_to :pos_token

  # 権限ごとの有効時間。現金が動く操作は短くする
  DEFAULT_TTL = 30.minutes
  TTL = { "refund" => 10.minutes, "discount" => 5.minutes }.freeze

  scope :active, -> { where(used_at: nil).where("operator_approvals.expires_at > ?", Time.current) }

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  # 承認を発行し、[レコード, 平文トークン] を返す
  def self.issue!(employee:, pos_token:, permission: nil)
    token = SecureRandom.urlsafe_base64(32)
    record = create!(
      employee: employee, pos_token: pos_token, permission: permission.presence,
      token_digest: digest(token), expires_at: Time.current + TTL.fetch(permission.to_s, DEFAULT_TTL)
    )
    [ record, token ]
  end

  # この承認で permission の操作ができるか。権限を指定せずに認証した承認では操作できない
  def covers?(permission)
    self.permission == permission.to_s
  end

  # 一度きりの操作（返品・取消）で消費する。同時に使われた場合は片方だけ成功する
  def consume!(purpose)
    self.class.active.where(id: id).update_all(used_at: Time.current, used_for: purpose) == 1
  end

  # 期限切れから十分に経った承認を削除する（定期ジョブ用）
  def self.purge_expired!
    where("expires_at < ?", 90.days.ago).in_batches.delete_all
  end
end
