class AddAudienceTypeToCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :campaigns, :audience_type, :string, default: 'labels', null: false
  end
end
