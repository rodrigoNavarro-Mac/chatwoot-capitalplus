# Bitácora de conflictos que RevenueIntelligence::IdentityResolver no resuelve automáticamente.
# El resolver nunca fusiona revenue_contacts silenciosamente ni sobrescribe un campo no-nulo con
# un valor distinto — cualquier ambigüedad queda aquí como deuda de revisión manual explícita.
#
# == Schema Information
#
# Table name: revenue_identity_conflicts
#
#  id            :bigint           not null, primary key
#  candidate_ids :jsonb
#  conflict_type :string           not null
#  match_key     :string
#  raw_context   :jsonb
#  resolved      :boolean          default(FALSE), not null
#  resolved_at   :datetime
#  source        :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#
# Indexes
#
#  idx_on_account_id_conflict_type_640a2b91dc                   (account_id,conflict_type)
#  index_revenue_identity_conflicts_on_account_id_and_resolved  (account_id,resolved)
#
class RevenueIdentityConflict < ApplicationRecord
  # multiple_candidates: dos o más señales de identidad (zoho_lead_id, zoho_contact_id, teléfono,
  # email, chatwoot_contact_id) apuntan a revenue_contacts DISTINTOS para el mismo registro entrante.
  # field_mismatch: se intentó sobrescribir un campo no-nulo (ej. email) con un valor distinto.
  CONFLICT_TYPES = %w[multiple_candidates field_mismatch].freeze

  belongs_to :account

  validates :conflict_type, presence: true, inclusion: { in: CONFLICT_TYPES }

  scope :unresolved, -> { where(resolved: false) }
end
