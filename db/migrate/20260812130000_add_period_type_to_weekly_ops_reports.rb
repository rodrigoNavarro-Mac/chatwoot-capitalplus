# frozen_string_literal: true

class AddPeriodTypeToWeeklyOpsReports < ActiveRecord::Migration[7.1]
  def change
    add_column :weekly_ops_reports, :period_type, :string, null: false, default: 'week'

    remove_index :weekly_ops_reports, column: [:inbox_id, :period_start], name: 'index_weekly_ops_reports_on_inbox_and_period_start'
    add_index :weekly_ops_reports, [:inbox_id, :period_start, :period_type], unique: true,
                                                                             name: 'index_weekly_ops_reports_on_inbox_period_start_type'
  end
end
