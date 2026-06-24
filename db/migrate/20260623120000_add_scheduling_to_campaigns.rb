class AddSchedulingToCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :campaigns, :delay_min_seconds, :integer, default: 300, null: false
    add_column :campaigns, :delay_max_seconds, :integer, default: 420, null: false
    add_column :campaigns, :send_window_start, :string, default: '09:00', null: false
    add_column :campaigns, :send_window_end, :string, default: '19:00', null: false
  end
end
