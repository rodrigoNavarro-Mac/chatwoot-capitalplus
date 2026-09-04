# Señal con estado (abierta/resuelta) sobre una regla determinística de Fase 4 — 'risk' (deals
# estancados, leads sin contactar, citas sin visita verificada) o 'data_quality' (inconsistencias
# del propio CRM). Ver RevenueIntelligence::RiskSignalRecorder para cómo se abre/cierra.
# == Schema Information
#
# Table name: revenue_risk_signals
#
#  id                :bigint           not null, primary key
#  category          :string           not null
#  context           :jsonb
#  detected_at       :datetime         not null
#  first_detected_at :datetime         not null
#  resolved_at       :datetime
#  severity          :string           default("medium"), not null
#  signal_type       :string           not null
#  subject_type      :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  subject_id        :bigint           not null
#
# Indexes
#
#  idx_on_account_id_category_resolved_at_33d7075598         (account_id,category,resolved_at)
#  idx_revenue_risk_signals_open_dedup                       (account_id,category,signal_type,subject_type,subject_id) UNIQUE WHERE (resolved_at IS NULL)
#  index_revenue_risk_signals_on_account_id_and_signal_type  (account_id,signal_type)
#
class RevenueRiskSignal < ApplicationRecord
  CATEGORIES = %w[risk data_quality].freeze
  SEVERITIES = %w[low medium high].freeze

  belongs_to :account

  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :severity, presence: true, inclusion: { in: SEVERITIES }
  validates :signal_type, :subject_type, :subject_id, :first_detected_at, :detected_at, presence: true

  scope :open, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }
end
