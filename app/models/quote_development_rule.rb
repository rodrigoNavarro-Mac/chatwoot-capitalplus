# == Schema Information
#
# Table name: quote_development_rules
#
#  id                 :bigint           not null, primary key
#  desarrollo         :string           not null
#  msi_auto_max_plazo :integer          not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#
# Indexes
#
#  index_quote_development_rules_on_account_id_and_desarrollo  (account_id,desarrollo) UNIQUE
#
# Regla por desarrollo (Zoho "Desarrollo") que gobierna Quotes::CalculateAndAttachService: con
# `plazos <= msi_auto_max_plazo` la cotización se cotiza automáticamente a meses sin intereses por
# todo el plazo; con `plazos` mayor, la cotización queda pendiente de autorización (ver
# Quote#authorization_status) y su PDF no se puede descargar hasta que se apruebe.
class QuoteDevelopmentRule < ApplicationRecord
  belongs_to :account

  validates :desarrollo, presence: true, uniqueness: { scope: :account_id }
  validates :msi_auto_max_plazo, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:desarrollo) }
end
