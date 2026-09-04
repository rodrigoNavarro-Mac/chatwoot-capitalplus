# Espejo analítico de un Zoho Deal. Ver RevenueIntelligence::DealMapper para el mapeo de campos —
# won/lost se derivan estrictamente de WON_STAGE/LOST_STAGE, nunca de "Apartado" (intención
# fuerte previa al cierre, no un cierre en sí).
#
# == Schema Information
#
# Table name: revenue_deals
#
#  id                 :bigint           not null, primary key
#  amount             :decimal(14, 2)
#  campaign_source    :string
#  closing_date       :date
#  created_at_source  :datetime
#  desarrollo         :string
#  expected_revenue   :decimal(14, 2)
#  lead_source        :string
#  lost               :boolean          default(FALSE), not null
#  owner_name         :string
#  pipeline           :string
#  probability        :decimal(5, 2)
#  quote_fields       :jsonb
#  raw_payload        :jsonb
#  reason_for_loss    :string
#  stage              :string
#  stage_modified_at  :datetime
#  synced_at          :datetime
#  won                :boolean          default(FALSE), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  owner_id           :string
#  revenue_contact_id :bigint
#  revenue_lead_id    :bigint
#  zoho_deal_id       :string           not null
#
# Indexes
#
#  index_revenue_deals_on_account_id_and_desarrollo          (account_id,desarrollo)
#  index_revenue_deals_on_account_id_and_revenue_contact_id  (account_id,revenue_contact_id)
#  index_revenue_deals_on_account_id_and_revenue_lead_id     (account_id,revenue_lead_id)
#  index_revenue_deals_on_account_id_and_stage               (account_id,stage)
#  index_revenue_deals_on_account_id_and_stage_modified_at   (account_id,stage_modified_at)
#  index_revenue_deals_on_account_id_and_won_and_lost        (account_id,won,lost)
#  index_revenue_deals_on_account_id_and_zoho_deal_id        (account_id,zoho_deal_id) UNIQUE
#
class RevenueDeal < ApplicationRecord
  # Valores reales confirmados del picklist Stage de Zoho Deals para esta cuenta.
  WON_STAGE = 'Cerrado ganado'.freeze
  LOST_STAGE = 'Cerrado perdido'.freeze
  RESERVED_STAGE = 'Apartado'.freeze

  belongs_to :account
  belongs_to :revenue_contact, optional: true
  belongs_to :revenue_lead, optional: true
  has_many :revenue_stage_events, dependent: :nullify
  has_many :revenue_appointments, dependent: :nullify

  validates :zoho_deal_id, presence: true, uniqueness: { scope: :account_id }

  scope :won, -> { where(won: true) }
  scope :lost, -> { where(lost: true) }
  scope :open, -> { where(won: false, lost: false) }
end
