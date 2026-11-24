# 全端末のジャーナルを検証し、控え（JournalAnchor）を取る。不整合はログとSentryに通知する。
class JournalVerificationJob < ApplicationJob
  def perform
    PosToken.find_each do |pos_token|
      issues = JournalEntry.verify_chain(pos_token)
      if issues.empty?
        JournalAnchor.capture!(pos_token)
      else
        message = "ジャーナルの不整合 POS##{pos_token.id}: #{issues.first(5).join(' / ')}（計#{issues.size}件）"
        Rails.logger.error message
        Sentry.capture_message(message, level: :error) if defined?(Sentry)
      end
    end
  end
end
