class CreateCadenceDefinitions < ActiveRecord::Migration[7.1]
  def change
    create_table :cadence_definitions do |t|
      t.bigint :account_id, null: false
      t.bigint :inbox_id, null: false

      t.string :name, null: false
      t.string :segment_value
      t.boolean :is_default, null: false, default: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :cadence_definitions, :account_id
    add_index :cadence_definitions, :inbox_id
    add_index :cadence_definitions, :inbox_id, unique: true, where: '(is_default = true)',
                                               name: 'idx_one_default_cadence_definition_per_inbox'
  end
end
