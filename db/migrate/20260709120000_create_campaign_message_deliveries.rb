class CreateCampaignMessageDeliveries < ActiveRecord::Migration[7.1]
  def change
    create_table :campaign_message_deliveries do |t|
      t.bigint :campaign_id, null: false
      t.bigint :account_id, null: false
      t.string :audience_type, null: false
      t.bigint :contact_id
      t.bigint :message_id
      t.string :phone_number, null: false
      t.string :source_id
      t.string :status, null: false, default: 'queued'
      t.text :failed_reason
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :read_at
      t.datetime :failed_at
      t.datetime :responded_at
      t.bigint :response_message_id
      t.bigint :response_conversation_id

      t.timestamps
    end

    add_index :campaign_message_deliveries, :campaign_id
    add_index :campaign_message_deliveries, :source_id, unique: true, where: 'source_id IS NOT NULL'
    add_index :campaign_message_deliveries, [:account_id, :phone_number]
    add_index :campaign_message_deliveries, :contact_id
  end
end
