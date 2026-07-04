# 電子ジャーナルを追記型（改ざん検知可能）にするためのハッシュチェーン用カラム。
# - sequence_number: 端末ごとの欠番検知用連番（pos_tokens.next_journal_sequence で採番）
# - previous_hash / entry_hash: 直前エントリのハッシュを含めて SHA-256 を計算し連鎖させる。
#   1件でも改変・削除されると以降の全ハッシュが不整合になる。
# 既存行は NULL のまま（チェーン開始前のレガシー扱い）。
class AddIntegrityChainToJournalEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :journal_entries, :sequence_number, :bigint
    add_column :journal_entries, :previous_hash, :string
    add_column :journal_entries, :entry_hash, :string

    add_index :journal_entries, [ :pos_token_id, :sequence_number ],
              unique: true, where: "sequence_number IS NOT NULL",
              name: "index_journal_entries_on_pos_sequence"

    add_column :pos_tokens, :next_journal_sequence, :bigint, null: false, default: 1
  end
end
