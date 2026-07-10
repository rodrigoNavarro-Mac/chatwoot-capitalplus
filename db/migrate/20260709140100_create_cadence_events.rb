class CreateCadenceEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :cadence_events do |t|
      t.bigint :account_id, null: false
      t.bigint :cadence_enrollment_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :contact_id
      t.string :event_type, null: false
      t.integer :step
      t.string :template_key
      t.string :actor_type
      t.bigint :actor_id
      t.datetime :occurred_at, null: false
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :cadence_events, :cadence_enrollment_id
    add_index :cadence_events, [:account_id, :event_type, :occurred_at]
    add_index :cadence_events, :conversation_id
  end
end
