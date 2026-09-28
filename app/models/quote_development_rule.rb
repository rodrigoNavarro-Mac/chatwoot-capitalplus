# == Schema Information
#
# Table name: quote_development_rules
#
#  id         :bigint           not null, primary key
#  desarrollo :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
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
class QuoteDevelopmentRule < ApplicationRecord
  belongs_to :account
  has_many :quote_development_rule_tiers, -> { order(Arel.sql('hasta_meses IS NULL, hasta_meses ASC')) },
           dependent: :destroy, inverse_of: :quote_development_rule
  accepts_nested_attributes_for :quote_development_rule_tiers, allow_destroy: true

  validates :desarrollo, presence: true, uniqueness: { scope: :account_id }
  validate :tiers_present, :tiers_have_valid_boundaries

  scope :ordered, -> { order(:desarrollo) }

  # Primer tramo (en orden ascendente de hasta_meses, con el "sin límite" al final) que cubre este
  # plazo. nil si la regla no tiene tramos aplicables (no debería pasar si tiers_present pasó).
  def tier_for(plazos)
    quote_development_rule_tiers.detect { |tier| tier.hasta_meses.nil? || plazos <= tier.hasta_meses }
  end

  private

  def active_tiers
    quote_development_rule_tiers.reject(&:marked_for_destruction?)
  end

  def tiers_present
    errors.add(:quote_development_rule_tiers, 'debe tener al menos un tramo') if active_tiers.empty?
  end

  def tiers_have_valid_boundaries
    open_ended = active_tiers.select { |tier| tier.hasta_meses.nil? }
    errors.add(:base, 'solo puede haber un tramo sin límite superior de meses') if open_ended.size > 1

    limits = active_tiers.filter_map(&:hasta_meses)
    errors.add(:base, 'los límites de meses de los tramos deben ser únicos') if limits.uniq.size != limits.size
  end
end
