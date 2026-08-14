class AddContactNameToCampaignMessageDeliveries < ActiveRecord::Migration[7.1]
  def change
    add_column :campaign_message_deliveries, :contact_name, :string
  end
end
