class CreateCadenceStepDefinitions < ActiveRecord::Migration[7.1]
  def change
    create_table :cadence_step_definitions do |t|
      t.bigint :account_id, null: false
      t.bigint :inbox_id, null: false

      t.integer :position, null: false
      t.string :label
      t.string :template_key, null: false

      t.string :template_name, null: false
      t.string :template_language, null: false, default: 'es_MX'
      t.string :template_namespace

      t.string :schedule_type, null: false
      t.integer :offset_minutes
      t.integer :day_offset
      t.string :time_of_day

      t.integer :wait_window_minutes, null: false

      t.boolean :creates_call_task, null: false, default: false
      t.boolean :active, null: false, default: true

      t.string :media_url
      t.string :media_type
      t.string :media_name

      t.timestamps
    end

    add_index :cadence_step_definitions, %i[inbox_id position], unique: true, name: 'idx_cadence_step_definitions_on_inbox_and_position'
    add_index :cadence_step_definitions, %i[inbox_id template_key], unique: true, name: 'idx_cadence_step_definitions_on_inbox_and_key'
    add_index :cadence_step_definitions, :account_id
  end
end
