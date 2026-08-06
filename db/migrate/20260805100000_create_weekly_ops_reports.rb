# frozen_string_literal: true

class CreateWeeklyOpsReports < ActiveRecord::Migration[7.1]
  def change
    create_table :weekly_ops_reports do |t|
      t.bigint :account_id, null: false
      t.bigint :inbox_id, null: false
      t.bigint :generated_by_id
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.string :status, null: false, default: 'pending'
      t.jsonb :kpis, null: false, default: {}
      t.text :llm_analysis

      t.timestamps
    end

    add_index :weekly_ops_reports, [:inbox_id, :period_start], unique: true, name: 'index_weekly_ops_reports_on_inbox_and_period_start'
    add_index :weekly_ops_reports, :account_id
    add_index :weekly_ops_reports, :generated_by_id
  end
end
