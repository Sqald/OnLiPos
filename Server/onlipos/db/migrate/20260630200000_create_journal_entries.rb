class CreateJournalEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :journal_entries do |t|
      t.references :user,      null: false, foreign_key: true
      t.references :store,     null: false, foreign_key: true
      t.references :pos_token, null: false, foreign_key: true
      t.references :employee,  null: true,  foreign_key: true
      t.integer    :entry_type, null: false
      t.string     :receipt_number
      t.datetime   :printed_at, null: false
      t.jsonb      :payload,    null: false, default: {}

      t.timestamps
    end

    add_index :journal_entries, [ :pos_token_id, :printed_at ]
    add_index :journal_entries, [ :store_id,     :printed_at ]
  end
end
