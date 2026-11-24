# 電子ジャーナルの保護
# - journal_anchors: 端末ごとの「何番まで・どのハッシュか」をアプリの鍵で署名して控える（末尾削除の検知）
# - DBトリガー（lib/tasks/journal_protection.rake）で UPDATE / DELETE / TRUNCATE を拒否する
class ProtectJournalEntries < ActiveRecord::Migration[8.1]
  def up
    create_table :journal_anchors do |t|
      t.references :pos_token, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :sequence_number, null: false
      t.string :entry_hash, null: false
      t.string :signature, null: false
      t.datetime :created_at, null: false
      t.index [ :pos_token_id, :sequence_number ]
    end
    JournalProtection.install!(connection)
  end

  def down
    JournalProtection.uninstall!(connection)
    drop_table :journal_anchors
  end
end
