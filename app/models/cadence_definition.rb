# == Schema Information
#
# Table name: cadence_definitions
#
#  id            :bigint           not null, primary key
#  active        :boolean          default(TRUE), not null
#  is_default    :boolean          default(FALSE), not null
#  name          :string           not null
#  segment_value :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  inbox_id      :bigint           not null
#
# Indexes
#
#  idx_one_default_cadence_definition_per_inbox  (inbox_id) UNIQUE WHERE (is_default = true)
#  index_cadence_definitions_on_account_id       (account_id)
#  index_cadence_definitions_on_inbox_id         (inbox_id)
#
# Una cadencia completa (conjunto ordenado de CadenceStepDefinition) para un inbox.
# segment_value permite dirigirla a los leads cuyo "razon_compra" (ver
# Cadences::RazonCompraResolver) coincida con ese valor; varias CadenceDefinition activas
# pueden compartir el mismo segment_value para correr un A/B/N test entre ellas —
# Cadences::CadenceDefinitionResolver reparte los leads nuevos por conteo (la que tenga
# menos enrollments hasta ahora). is_default marca la que atrapa a los leads sin segmento
# que matchee (a lo sumo una por inbox).
class CadenceDefinition < ApplicationRecord
  belongs_to :account
  belongs_to :inbox

  has_many :cadence_step_definitions, dependent: :destroy
  has_many :cadence_enrollments, dependent: :nullify

  validates :name, presence: true
  validates :is_default, uniqueness: { scope: :inbox_id }, if: :is_default?

  scope :active, -> { where(active: true) }
  scope :for_inbox, ->(inbox_id) { where(inbox_id: inbox_id) }
  scope :matching_segment, ->(value) { where(segment_value: value) }

  # Solo puede haber un default por inbox (índice único parcial); despejar el anterior y
  # marcar este en una transacción evita chocar contra esa restricción al reasignarlo.
  def mark_as_default!
    CadenceDefinition.transaction do
      CadenceDefinition.for_inbox(inbox_id).where(is_default: true).update_all(is_default: false) # rubocop:disable Rails/SkipsModelValidations
      update!(is_default: true)
    end
  end
end
