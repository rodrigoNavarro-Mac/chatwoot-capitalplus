# == Schema Information
#
# Table name: whatsapp_template_inbox_assignments
#
#  id            :bigint           not null, primary key
#  media_name    :string
#  media_url     :string
#  template_name :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  inbox_id      :bigint           not null
#
# Indexes
#
#  idx_on_account_id_inbox_id_50dc94ef25                          (account_id,inbox_id)
#  index_wa_template_inbox_assignments_on_account_template_inbox  (account_id,template_name,inbox_id) UNIQUE
#  index_whatsapp_template_inbox_assignments_on_account_id        (account_id)
#  index_whatsapp_template_inbox_assignments_on_inbox_id          (inbox_id)
#

class WhatsappTemplateInboxAssignment < ApplicationRecord
  belongs_to :account
  belongs_to :inbox

  validates :template_name, presence: true
  validates :template_name, uniqueness: { scope: [:account_id, :inbox_id] }
end
