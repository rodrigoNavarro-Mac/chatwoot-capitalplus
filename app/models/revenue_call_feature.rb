# Proyección analítica 1:1 de CallAnalysis — ver RevenueIntelligence::ExtractCallFeaturesJob.
# Los jsonb originales (qualification_map, scorecard, metrics, objections, risks) siguen viviendo
# en call_analyses; esta tabla nunca es la fuente de verdad, solo una vista aplanada para Fase 3.
# == Schema Information
#
# Table name: revenue_call_features
#
#  id                            :bigint           not null, primary key
#  closed_questions              :integer          default(0), not null
#  confidence                    :string
#  conversation_type             :string
#  cta_used                      :boolean          default(FALSE), not null
#  intent_level                  :string
#  longest_monologue_seconds     :integer
#  objection_count               :integer          default(0), not null
#  open_questions                :integer          default(0), not null
#  outcome_at                    :datetime
#  outcome_type                  :string
#  qual_alternativas_competencia :boolean          default(FALSE), not null
#  qual_bloqueo_principal        :boolean          default(FALSE), not null
#  qual_forma_pago_credito       :boolean          default(FALSE), not null
#  qual_intencion_vivir_invertir :boolean          default(FALSE), not null
#  qual_momento_compra           :boolean          default(FALSE), not null
#  qual_necesidad_concreta       :boolean          default(FALSE), not null
#  qual_presupuesto              :boolean          default(FALSE), not null
#  qual_requisito_indispensable  :boolean          default(FALSE), not null
#  qual_siguiente_paso           :boolean          default(FALSE), not null
#  qual_tomadores_decision       :boolean          default(FALSE), not null
#  qualification_completeness    :decimal(5, 4)
#  qualification_count           :integer          default(0), not null
#  risk_count                    :integer          default(0), not null
#  role                          :string
#  score_reading                 :string
#  score_total                   :decimal(6, 2)
#  started_at                    :datetime
#  talk_ratio                    :decimal(5, 4)
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  account_id                    :bigint           not null
#  agent_id                      :bigint
#  call_analysis_id              :bigint           not null
#  call_id                       :bigint           not null
#  revenue_contact_id            :bigint
#  zoho_deal_id                  :string
#
# Indexes
#
#  idx_on_account_id_agent_id_started_at_4084dbc122            (account_id,agent_id,started_at)
#  idx_on_account_id_revenue_contact_id_65c81fc7f5             (account_id,revenue_contact_id)
#  index_revenue_call_features_on_account_id_and_call_id       (account_id,call_id) UNIQUE
#  index_revenue_call_features_on_account_id_and_intent_level  (account_id,intent_level)
#  index_revenue_call_features_on_account_id_and_outcome_type  (account_id,outcome_type)
#
class RevenueCallFeature < ApplicationRecord
  belongs_to :account
  belongs_to :revenue_contact, optional: true

  validates :call_id, presence: true, uniqueness: { scope: :account_id }
  validates :call_analysis_id, presence: true
end
