class AddStepsSnapshotToCadenceEnrollments < ActiveRecord::Migration[7.1]
  def change
    add_column :cadence_enrollments, :steps_snapshot, :jsonb, null: false, default: []
  end
end
