# 登録・変更・削除を操作履歴（AuditLog）に残す。秘密情報の値は記録しない。
module Auditable
  extend ActiveSupport::Concern

  IGNORED = %w[id created_at updated_at last_used_at last_ip app_version platform next_receipt_sequence next_journal_sequence
               failed_attempts locked_at sign_in_count current_sign_in_at last_sign_in_at current_sign_in_ip last_sign_in_ip
               remember_created_at otp_last_used_timestep session_version webauthn_id].freeze
  SECRET = /password|digest|token|secret|ciphertext|_code/

  included do
    after_create  { record_audit("create") }
    after_update  { record_audit("update") }
    after_destroy { record_audit("destroy") }
  end

  def audit_name = try(:name)

  private

  def record_audit(action)
    changes = action == "destroy" ? {} : saved_changes.except(*IGNORED)
    return if action == "update" && changes.empty?

    changes = changes.to_h { |key, values| [ key, key.match?(SECRET) && key != "code" ? "[変更あり]" : values ] }
    AuditLog.record(action, target: self, details: changes)
  end
end
