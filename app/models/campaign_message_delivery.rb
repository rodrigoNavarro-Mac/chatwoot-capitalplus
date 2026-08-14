# == Schema Information
#
# Table name: campaign_message_deliveries
#
#  id                       :bigint           not null, primary key
#  audience_type            :string           not null
#  contact_name             :string
#  delivered_at             :datetime
#  failed_at                :datetime
#  failed_reason            :text
#  phone_number             :string           not null
#  read_at                  :datetime
#  responded_at             :datetime
#  sent_at                  :datetime
#  status                   :string           default("queued"), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#  campaign_id              :bigint           not null
#  contact_id               :bigint
#  message_id               :bigint
#  response_conversation_id :bigint
#  response_message_id      :bigint
#  source_id                :string
#
# Indexes
#
#  idx_on_account_id_phone_number_b81823726f         (account_id,phone_number)
#  index_campaign_message_deliveries_on_campaign_id  (campaign_id)
#  index_campaign_message_deliveries_on_contact_id   (contact_id)
#  index_campaign_message_deliveries_on_source_id    (source_id) UNIQUE WHERE (source_id IS NOT NULL)
#
class CampaignMessageDelivery < ApplicationRecord
  belongs_to :campaign
  belongs_to :account
  belongs_to :contact, optional: true
  belongs_to :message, optional: true

  enum status: { queued: 'queued', sent: 'sent', delivered: 'delivered', read: 'read', failed: 'failed' }

  validates :phone_number, presence: true
  validates :audience_type, presence: true
end
