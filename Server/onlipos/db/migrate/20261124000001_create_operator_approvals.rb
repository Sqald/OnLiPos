# 担当者のPIN認証結果（承認）。返品・精算などの操作APIは、この承認トークンの提示を必須にする。
class CreateOperatorApprovals < ActiveRecord::Migration[8.1]
  def change
    create_table :operator_approvals do |t|
      t.references :employee, null: false, foreign_key: true
      t.references :pos_token, null: false, foreign_key: true
      t.string :permission
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.string :used_for
      t.datetime :created_at, null: false
      t.index :token_digest, unique: true
      t.index :expires_at
    end
  end
end
