class AddTimezoneToCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :campaigns, :timezone, :string, default: 'UTC'
  end
end
