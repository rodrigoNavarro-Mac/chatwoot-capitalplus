class CreateCadenceEnrollments < ActiveRecord::Migration[7.1]
  def change
    create_table :cadence_enrollments do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :contact_id
      t.bigint :inbox_id, null: false
      t.bigint :assignee_id
      t.string :cadence_name, null: false, default: 'cadencia_comercial_default'
      t.integer :current_step, null: false, default: 0
      t.string :status, null: false, default: 'active'
      t.datetime :last_template_sent_at
      t.datetime :last_lead_response_at
      t.datetime :next_action_at
      t.datetime :last_call_task_created_at
      t.string :stopped_reason

      t.timestamps
    end

    add_index :cadence_enrollments, :conversation_id, unique: true
    add_index :cadence_enrollments, [:account_id, :status]
    add_index :cadence_enrollments, :next_action_at
    add_index :cadence_enrollments, :contact_id
    add_index :cadence_enrollments, :assignee_id
  end
end
