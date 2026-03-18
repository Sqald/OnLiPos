class CreateProvisionings < ActiveRecord::Migration[8.1]
  def change
    create_table :provisionings do |t|
      t.string :name, null: false
      t.references :user, null: false, foreign_key: true
      t.references :store, null: false, foreign_key: true
      t.jsonb :store_context, null: false, default: {}
      t.jsonb :hardware_settings, null: false, default: {}

      t.timestamps
    end
  end
end
