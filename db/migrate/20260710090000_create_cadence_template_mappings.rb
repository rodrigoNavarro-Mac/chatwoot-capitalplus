class CreateCadenceTemplateMappings < ActiveRecord::Migration[7.1]
  def change
    create_table :cadence_template_mappings do |t|
      t.bigint :account_id, null: false
      t.bigint :inbox_id, null: false
      t.string :template_key, null: false
      t.string :name, null: false
      t.string :language, null: false, default: 'es_MX'
      t.string :namespace

      t.timestamps
    end

    add_index :cadence_template_mappings, [:inbox_id, :template_key], unique: true, name: 'idx_cadence_template_mappings_on_inbox_and_key'
    add_index :cadence_template_mappings, :account_id
  end
end
