# Resultado del análisis estructurado por LLM de una llamada de Aircall — 1:1 con `Call` (llave
# de idempotencia: call_id, único). Tabla separada del modelo `Call` (compartido por
# twilio/whatsapp/aircall) a propósito: permite re-análisis (nuevo prompt/pesos) sin tocar el
# registro crudo de la llamada, y auditar qué versión de prompt/config produjo cada score. Ver
# CallAnalysis::AnalyzeJob para la orquestación y CallAnalysis::StructuredAnalysisLlmService para
# el contrato de extracción.
# == Schema Information
#
# Table name: call_analyses
#
#  id                       :bigint           not null, primary key
#  analyzed_at              :datetime
#  attempts                 :integer          default(0), not null
#  confidence               :string
#  conversation_type        :string
#  error_message            :text
#  error_step               :string
#  evidence                 :jsonb
#  intent_level             :string
#  last_attempted_at        :datetime
#  llm_model                :string
#  llm_raw_response         :jsonb
#  metrics                  :jsonb
#  objections               :jsonb
#  outcome_at               :datetime
#  outcome_type             :string
#  prompt_version           :string
#  qualification_map        :jsonb
#  risks                    :jsonb
#  role                     :string
#  scorecard                :jsonb
#  scorecard_config_version :string
#  status                   :string           default("pending"), not null
#  zoho_deal_stage          :string
#  zoho_note_error          :text
#  zoho_note_status         :string           default("not_applicable"), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#  agent_id                 :bigint
#  call_id                  :bigint           not null
#  inbox_id                 :bigint           not null
#  provider_call_id         :string           not null
#  zoho_deal_id             :string
#  zoho_note_id             :string
#
# Indexes
#
#  idx_on_account_id_role_conversation_type_7c172e6256             (account_id,role,conversation_type)
#  index_call_analyses_on_account_id_and_agent_id_and_analyzed_at  (account_id,agent_id,analyzed_at)
#  index_call_analyses_on_account_id_and_inbox_id_and_analyzed_at  (account_id,inbox_id,analyzed_at)
#  index_call_analyses_on_account_id_and_status                    (account_id,status)
#  index_call_analyses_on_call_id                                  (call_id) UNIQUE
#
class CallAnalysis < ApplicationRecord
  STATUSES = %w[pending processing completed failed].freeze
  ROLES = %w[setter asesor].freeze
  CONVERSATION_TYPES = %w[prospeccion_inicial seguimiento_pre_cita confirmacion_cita post_visita reactivacion].freeze
  CONFIDENCE_LEVELS = %w[low medium high].freeze
  OUTCOME_TYPES = %w[cita seguimiento accion_sin_fecha solo_informacion sin_avance].freeze
  INTENT_LEVELS = %w[alta media baja].freeze
  ZOHO_NOTE_STATUSES = %w[not_applicable pending sent failed].freeze

  belongs_to :account
  belongs_to :call
  belongs_to :inbox
  belongs_to :agent, class_name: 'User', optional: true

  validates :call_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :role, inclusion: { in: ROLES }, allow_nil: true
  validates :conversation_type, inclusion: { in: CONVERSATION_TYPES }, allow_nil: true
  validates :confidence, inclusion: { in: CONFIDENCE_LEVELS }, allow_nil: true
  validates :outcome_type, inclusion: { in: OUTCOME_TYPES }, allow_nil: true
  validates :intent_level, inclusion: { in: INTENT_LEVELS }, allow_nil: true
  validates :zoho_note_status, inclusion: { in: ZOHO_NOTE_STATUSES }

  scope :completed_scope, -> { where(status: 'completed') }
  scope :needs_review, -> { where(status: 'failed').or(where(error_step: 'low_confidence')) }
  scope :retryable, ->(max_attempts) { where(status: 'failed').where('attempts < ?', max_attempts) }

  # Reusa el medidor de créditos de Captain (mismo criterio que Llm::SpeechToTextService.available_for?)
  # en vez de crear un segundo sistema de billing para el feature flag `call_intelligence`.
  def self.available_for?(account)
    return false unless account.feature_enabled?('call_intelligence')

    account.usage_limits[:captain][:responses][:current_available].positive?
  end

  def completed?
    status == 'completed'
  end

  def low_confidence?
    confidence == 'low'
  end

  # Solo se envía nota a Zoho para análisis con confianza suficiente (política default,
  # configurable a futuro) — una clasificación de baja confianza queda auditable en Chatwoot pero
  # no debe llegarle al asesor/gerencia dentro del CRM todavía.
  def should_publish_zoho_note?
    completed? && !low_confidence?
  end

  def total_score
    scorecard['total_score']
  end

  def score_reading
    scorecard['reading']
  end
end
