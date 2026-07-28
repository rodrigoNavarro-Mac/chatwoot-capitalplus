class AddSendRetryCountToCadenceEnrollments < ActiveRecord::Migration[7.1]
  def change
    add_column :cadence_enrollments, :send_retry_count, :integer, default: 0, null: false
  end
end
