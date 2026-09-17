# Espejo analítico de un Zoho Deal. Ver RevenueIntelligence::DealMapper para el mapeo de campos —
# won/lost se derivan estrictamente de WON_STAGE/LOST_STAGE, nunca de "Apartado" (intención
# fuerte previa al cierre, no un cierre en sí).
#
# == Schema Information
#
# Table name: revenue_deals
#
#  id                    :bigint           not null, primary key
#  ad_account_name       :string
#  adset_name            :string
#  advert_name           :string
#  amount                :decimal(14, 2)
#  campaign_name         :string
#  campaign_source       :string
#  closing_date          :date
#  created_at_source     :datetime
#  desarrollo            :string
#  expected_revenue      :decimal(14, 2)
#  form_name             :string
#  lead_source           :string
#  lead_type             :string
#  lost                  :boolean          default(FALSE), not null
#  owner_name            :string
#  page_name             :string
#  pipeline              :string
#  platform              :string
#  probability           :decimal(5, 2)
#  qualification_channel :string
#  quote_fields          :jsonb
#  raw_payload           :jsonb
#  reason_for_loss       :string
#  stage                 :string
#  stage_modified_at     :datetime
#  synced_at             :datetime
#  won                   :boolean          default(FALSE), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  ad_account_id         :string
#  adset_id              :string
#  advert_id             :string
#  campaign_id           :string
#  form_id               :string
#  owner_id              :string
#  page_id               :string
#  revenue_contact_id    :bigint
#  revenue_lead_id       :bigint
#  social_lead_id        :string
#  zoho_deal_id          :string           not null
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
  SCHEDULED_STAGE = 'Agendo cita'.freeze

  # Etapas cuyo `reference_value` (el string que Zoho realmente guarda en el campo Stage del Deal,
  # confirmado vía RevenueIntelligence::DealMapper/StageHistoryBuilder leyendo payload['Stage']
  # directo) implican que YA hubo una visita, aunque el deal avance o se pierda después. Verificado
  # 2026-09-17 contra el picklist real de Stage en Zoho (getFields del módulo Deals de esta cuenta):
  # el display_value "Cotizado con visita" tiene reference_value "Cotizado" (NO "Needs Analysis",
  # que es el actual_value en inglés que usa V2::Reports::SalesFunnelBuilder::VISITA_EFECTIVA_STAGES
  # — esa lista lee additional_attributes['external'], una fuente distinta que sí cachea en inglés;
  # no aplica aquí). Antes de este fix, un deal que llegó a "Cotizado"/Apartado/Cerrado ganado sin
  # pasar por una fila de Stage_History literalmente igual a "Visita efectiva" no contaba como
  # visita, dejando "Visitas" en 0 en el Overview aunque el deal ya hubiera avanzado más allá de la
  # visita (bug real reportado por el usuario: un deal en Cotizado con Visitas=0).
  VISIT_STAGES = ['Visita efectiva', 'Cotizado', RESERVED_STAGE, WON_STAGE].freeze

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
