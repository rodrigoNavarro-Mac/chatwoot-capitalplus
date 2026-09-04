# Ancla de identidad de Revenue Intelligence — ver RevenueIntelligence::IdentityResolver para el
# algoritmo de resolución. Nunca se escribe desde aquí hacia `contacts`; `chatwoot_contact_id` es
# una referencia lógica de solo lectura.
#
# == Schema Information
#
# Table name: revenue_contacts
#
#  id                  :bigint           not null, primary key
#  email               :string
#  first_seen_at       :datetime         not null
#  last_seen_at        :datetime         not null
#  normalized_phone    :string
#  raw_phone           :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  chatwoot_contact_id :bigint
#  zoho_contact_id     :string
#  zoho_deal_id        :string
#  zoho_lead_id        :string
#
# Indexes
#
#  idx_revenue_contacts_on_account_cw_contact      (account_id,chatwoot_contact_id) UNIQUE WHERE (chatwoot_contact_id IS NOT NULL)
#  idx_revenue_contacts_on_account_phone           (account_id,normalized_phone) UNIQUE WHERE (normalized_phone IS NOT NULL)
#  idx_revenue_contacts_on_account_zoho_contact    (account_id,zoho_contact_id) UNIQUE WHERE (zoho_contact_id IS NOT NULL)
#  idx_revenue_contacts_on_account_zoho_lead       (account_id,zoho_lead_id) UNIQUE WHERE (zoho_lead_id IS NOT NULL)
#  index_revenue_contacts_on_account_id_and_email  (account_id,email)
#
class RevenueContact < ApplicationRecord
  belongs_to :account

  has_many :revenue_leads, dependent: :nullify
  has_many :revenue_deals, dependent: :nullify
  has_many :revenue_appointments, dependent: :nullify
  has_many :revenue_stage_events, dependent: :nullify

  validates :first_seen_at, :last_seen_at, presence: true
  validates :normalized_phone, uniqueness: { scope: :account_id }, allow_nil: true
  validates :zoho_lead_id, uniqueness: { scope: :account_id }, allow_nil: true
  validates :zoho_contact_id, uniqueness: { scope: :account_id }, allow_nil: true
  validates :chatwoot_contact_id, uniqueness: { scope: :account_id }, allow_nil: true
end
