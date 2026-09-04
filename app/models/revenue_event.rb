# Evento normalizado del journey — ver RevenueIntelligence::BuildEventsJob para cómo se puebla y
# el plan de Fase 2 para la tabla completa de qué produce cada event_type.
# == Schema Information
#
# Table name: revenue_events
#
#  id                 :bigint           not null, primary key
#  event_at           :datetime         not null
#  event_type         :string           not null
#  metadata           :jsonb
#  source_system      :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  agent_id           :bigint
#  call_id            :bigint
#  conversation_id    :bigint
#  revenue_contact_id :bigint
#  source_id          :string           not null
#  zoho_deal_id       :string
#  zoho_lead_id       :string
#
# Indexes
#
#  idx_on_account_id_revenue_contact_id_event_at_4e5b9d3616        (account_id,revenue_contact_id,event_at)
#  idx_revenue_events_dedup                                        (account_id,source_system,event_type,source_id) UNIQUE
#  index_revenue_events_on_account_id_and_call_id                  (account_id,call_id)
#  index_revenue_events_on_account_id_and_conversation_id          (account_id,conversation_id)
#  index_revenue_events_on_account_id_and_event_type_and_event_at  (account_id,event_type,event_at)
#
class RevenueEvent < ApplicationRecord
  EVENT_TYPES = %w[
    lead_created whatsapp_incoming whatsapp_outgoing first_response call_started call_answered
    call_missed call_analyzed lead_contacted lead_qualified deal_created appointment_created
    stage_changed visit_effective reserved closed_won closed_lost
  ].freeze

  belongs_to :account
  belongs_to :revenue_contact, optional: true

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :event_at, :source_system, :source_id, presence: true
end
