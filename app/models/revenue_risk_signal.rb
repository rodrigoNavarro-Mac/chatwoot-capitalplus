# Señal con estado (abierta/resuelta) sobre una regla determinística de Fase 4 — 'risk' (deals
# estancados, leads sin contactar, citas sin visita verificada) o 'data_quality' (inconsistencias
# del propio CRM). Ver RevenueIntelligence::RiskSignalRecorder para cómo se abre/cierra.
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
