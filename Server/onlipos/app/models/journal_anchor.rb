# 電子ジャーナルの控え。「この端末のジャーナルは、この時点で何番まで・どのハッシュだったか」を
# アプリの鍵で署名して保存する。ハッシュチェーンだけでは分からない末尾の削除や全体の作り直しを検知する。
class JournalAnchor < ApplicationRecord
  belongs_to :pos_token

  before_create { self.signature = self.class.sign(pos_token_id, sequence_number, entry_hash) }

  def self.sign(pos_token_id, sequence_number, entry_hash)
    key = Rails.application.key_generator.generate_key("onlipos/journal_anchor", 32)
    OpenSSL::HMAC.hexdigest("SHA256", key, [ pos_token_id, sequence_number, entry_hash ].join("|"))
  end

  # 端末ごとの最新エントリを控える（変化がなければ何もしない）
  def self.capture!(pos_token)
    entry = JournalEntry.where(pos_token_id: pos_token.id).where.not(sequence_number: nil).order(sequence_number: :desc).first
    return if entry.nil? || exists?(pos_token_id: pos_token.id, sequence_number: entry.sequence_number)

    create!(pos_token: pos_token, sequence_number: entry.sequence_number, entry_hash: entry.entry_hash)
  end

  def valid_signature?
    ActiveSupport::SecurityUtils.secure_compare(signature, self.class.sign(pos_token_id, sequence_number, entry_hash))
  end
end
