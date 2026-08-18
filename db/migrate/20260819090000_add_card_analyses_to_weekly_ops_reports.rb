class AddCardAnalysesToWeeklyOpsReports < ActiveRecord::Migration[7.1]
  def change
    add_column :weekly_ops_reports, :card_analyses, :jsonb, default: {}, null: false
  end
end
