class AddAudienceCountToCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :campaigns, :audience_count, :integer
  end
end
