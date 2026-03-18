class CreatePosTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :pos_tokens do |t|
      t.references :store, null: false, foreign_key: true
      t.references :provisioning, null: true, foreign_key: true
      t.string :token
      t.string :password_digest
      t.string :name
      t.string :ascii_name
      t.datetime :expires_at
      t.datetime :last_used_at
      t.bigint :next_receipt_sequence, null: false, default: 1

      t.timestamps
    end
    add_index :pos_tokens, :token, unique: true
  end
end
