# == Schema Information
#
# Table name: whatsapp_webhook_events
#
#  id              :bigint           not null, primary key
#  payload         :jsonb            not null
#  phone_number    :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  phone_number_id :string
#
# Indexes
#
#  index_whatsapp_webhook_events_on_created_at       (created_at)
#  index_whatsapp_webhook_events_on_phone_number_id  (phone_number_id)
#
class WhatsappWebhookEvent < ApplicationRecord
end
