# Historial append-only de cambios de `revenue_ad_spends.amount` -- ver Fase 22 (docs/
# investigacion-tesis-ia/27_IMPLEMENTACION_ATRIBUCION_FASE22.md) y el comentario de la migración
# `20261020190200_create_revenue_ad_spend_revisions.rb`. Nunca se actualiza ni se borra una fila
# ya creada (salvo cascada al borrar el `revenue_ad_spend` padre) -- es un log de auditoría, no
# un estado mutable. `observed_at` nunca debe ser posterior a `created_at` por más de el margen
# normal de ejecución del job (ver validación `observed_at_not_in_future`): backdatearlo
# artificialmente para simular un valor "conocido antes" invalidaría cualquier feature
# point-in-time construida sobre esta tabla.
# == Schema Information
#
# Table name: revenue_ad_spend_revisions
#
#  id                  :bigint           not null, primary key
#  amount              :decimal(14, 2)   not null
#  observed_at         :datetime         not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  revenue_ad_spend_id :bigint           not null
#
# Indexes
#
#  idx_revenue_ad_spend_revisions_lookup  (revenue_ad_spend_id,observed_at)
#
class RevenueAdSpendRevision < ApplicationRecord
  belongs_to :account
  belongs_to :revenue_ad_spend

  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :observed_at, presence: true
  validate :observed_at_not_in_future

  # Consulta point-in-time (Fase 22 §3/§4): el importe efectivamente conocido por
  # RevenueIntelligence en el instante `at`, sin mirar nunca una revisión posterior -- evita la
  # fuga temporal sutil ya documentada en Fase 16 §4 (reajustes dentro de la ventana de
  # recorrección de 7 días). Devuelve nil cuando no hay ninguna revisión conocida a esa fecha
  # (el llamador decide si eso significa "no construir la feature" o "usar un valor nulo
  # explícito" -- nunca se sustituye en este método por el valor final/actual).
  def self.known_amount_as_of(revenue_ad_spend_id, at)
    where(revenue_ad_spend_id: revenue_ad_spend_id).where('observed_at <= ?', at).order(observed_at: :desc).first&.amount
  end

  private

  def observed_at_not_in_future
    return if observed_at.blank?
    return if observed_at <= 1.minute.from_now # margen de tolerancia por reloj/latencia

    errors.add(:observed_at, 'no puede ser una fecha futura')
  end
end
