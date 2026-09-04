# Resumen "listo para leer" del journey de un RevenueLead — ver RevenueIntelligence::
# BuildJourneysJob para cómo se agrega a partir de revenue_events.
# == Schema Information
#
# Table name: revenue_lead_journeys
#
#  id                             :bigint           not null, primary key
#  appointment_at                 :datetime
#  avg_call_score                 :decimal(6, 2)
#  built_at                       :datetime
#  calls_answered                 :integer          default(0), not null
#  calls_attempted                :integer          default(0), not null
#  calls_missed                   :integer          default(0), not null
#  closed_at                      :datetime
#  cta_count                      :integer          default(0), not null
#  deal_created_at                :datetime
#  final_stage                    :string
#  first_answered_call_at         :datetime
#  first_call_at                  :datetime
#  first_response_at              :datetime
#  incoming_messages              :integer          default(0), not null
#  last_call_score                :decimal(6, 2)
#  latest_intent                  :string
#  lead_created_at                :datetime
#  lost                           :boolean          default(FALSE), not null
#  max_call_score                 :decimal(6, 2)
#  max_intent                     :string
#  objections_count               :integer          default(0), not null
#  outgoing_messages              :integer          default(0), not null
#  qualified_at                   :datetime
#  reserved_at                    :datetime
#  risks_count                    :integer          default(0), not null
#  time_to_appointment_seconds    :integer
#  time_to_close_seconds          :integer
#  time_to_first_call_seconds     :integer
#  time_to_first_response_seconds :integer
#  time_to_qualification_seconds  :integer
#  time_to_visit_seconds          :integer
#  total_call_seconds             :integer          default(0), not null
#  unique_agents                  :integer          default(0), not null
#  visit_at                       :datetime
#  won                            :boolean          default(FALSE), not null
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  account_id                     :bigint           not null
#  revenue_contact_id             :bigint
#  revenue_deal_id                :bigint
#  revenue_lead_id                :bigint           not null
#
# Indexes
#
#  idx_on_account_id_revenue_contact_id_e5770161d1                (account_id,revenue_contact_id)
#  index_revenue_lead_journeys_on_account_id_and_final_stage      (account_id,final_stage)
#  index_revenue_lead_journeys_on_account_id_and_revenue_lead_id  (account_id,revenue_lead_id) UNIQUE
#  index_revenue_lead_journeys_on_account_id_and_won_and_lost     (account_id,won,lost)
#
class RevenueLeadJourney < ApplicationRecord
  belongs_to :account
  belongs_to :revenue_lead
  belongs_to :revenue_contact, optional: true
  belongs_to :revenue_deal, optional: true

  validates :revenue_lead_id, uniqueness: { scope: :account_id }

  scope :won, -> { where(won: true) }
  scope :lost, -> { where(lost: true) }
end
