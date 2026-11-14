# == Schema Information
#
# Table name: quote_development_rules
#
#  id              :bigint           not null, primary key
#  desarrollo      :string           not null
#  interes_default :decimal(5, 2)
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#
# Indexes
#
#  index_quote_development_rules_on_account_id_and_desarrollo  (account_id,desarrollo) UNIQUE
#
# Regla por desarrollo (Zoho "Desarrollo") que gobierna Quotes::CalculateAndAttachService: una
# lista ordenada de tramos (QuoteDevelopmentRuleTier) por plazo — cada tramo decide si ese rango de
# meses se cotiza automáticamente a meses sin intereses y si requiere autorización antes de poder
# descargar el PDF (ver Quote#authorization_status). Reemplaza el umbral único original para
# permitir reglas de varios tramos (ver MigrateMsiAutoMaxPlazoToTiers).
#
# `interes_default` es la tasa anual (%) con la que se cotiza el desarrollo: es el valor fijo para
# quien no tiene permiso de editar el interés, el valor precargado en el formulario, y el que se usa
# siempre en cotizaciones desde un Deal de Zoho (ignora el "Interes" del Deal). nil = sin tasa
# propia, aplica FALLBACK_INTERES. Una regla puede tener solo la tasa, solo tramos, o ambos.
class QuoteDevelopmentRule < ApplicationRecord
  FALLBACK_INTERES = BigDecimal(8)
  belongs_to :account
  has_many :quote_development_rule_tiers, -> { order(Arel.sql('hasta_meses IS NULL, hasta_meses ASC')) },
           dependent: :destroy, inverse_of: :quote_development_rule
  accepts_nested_attributes_for :quote_development_rule_tiers, allow_destroy: true

  validates :desarrollo, presence: true, uniqueness: { scope: :account_id }
  validates :interes_default, numericality: { greater_than_or_equal_to: 0, less_than: 100 }, allow_nil: true
  validate :tiers_or_interes_present, :tiers_have_valid_boundaries

  scope :ordered, -> { order(:desarrollo) }

  # Tasa configurada del desarrollo, o nil si no tiene regla / la regla no define tasa.
  def self.configured_interes_for(account, desarrollo)
    return nil if desarrollo.blank?

    account.quote_development_rules.find_by(desarrollo: desarrollo)&.interes_default
  end

  def self.default_interes_for(account, desarrollo)
    configured_interes_for(account, desarrollo) || FALLBACK_INTERES
  end

  # Primer tramo (en orden ascendente de hasta_meses, con el "sin límite" al final) que cubre este
  # plazo. nil si la regla no tiene tramos (una regla puede definir solo el interés por defecto).
  def tier_for(plazos)
    quote_development_rule_tiers.detect { |tier| tier.hasta_meses.nil? || plazos <= tier.hasta_meses }
  end

  private

  def active_tiers
    quote_development_rule_tiers.reject(&:marked_for_destruction?)
  end

  def tiers_or_interes_present
    return if active_tiers.any? || interes_default.present?

    errors.add(:base, 'debe tener al menos un tramo o un interés por defecto')
  end

  def tiers_have_valid_boundaries
    open_ended = active_tiers.select { |tier| tier.hasta_meses.nil? }
    errors.add(:base, 'solo puede haber un tramo sin límite superior de meses') if open_ended.size > 1

    limits = active_tiers.filter_map(&:hasta_meses)
    errors.add(:base, 'los límites de meses de los tramos deben ser únicos') if limits.uniq.size != limits.size
  end
end
