class CreateCadenceCallTasks < ActiveRecord::Migration[7.1]
  def change
    create_table :cadence_call_tasks do |t|
      t.bigint :account_id, null: false
      t.bigint :cadence_enrollment_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :user_id
      t.integer :step, null: false
      t.string :status, null: false, default: 'pending'
      t.datetime :notified_at
      t.datetime :completed_at
      t.bigint :completed_by_id

      t.timestamps
    end

    add_index :cadence_call_tasks, [:cadence_enrollment_id, :step], unique: true, name: 'idx_cadence_call_tasks_on_enrollment_and_step'
    add_index :cadence_call_tasks, [:account_id, :status]
    add_index :cadence_call_tasks, :user_id
  end
end
