# Raw audit trail of every WhatsApp webhook call, persisted before signature
# verification or channel lookup runs. Docker container logs (the previous only
# record of these payloads) get wiped on every deploy since RAILS_LOG_TO_STDOUT
# has no backing volume, so a bug that rejects/drops a webhook downstream used to
# mean the payload was gone forever. This table survives deploys and lets a
# rejected webhook be inspected or replayed later.
class CreateWhatsappWebhookEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_webhook_events do |t|
      t.string :phone_number
      t.string :phone_number_id
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :whatsapp_webhook_events, :phone_number_id
    add_index :whatsapp_webhook_events, :created_at
  end
end
