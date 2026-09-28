# == Schema Information
#
# Table name: quote_development_rule_tiers
#
#  id                        :bigint           not null, primary key
#  hasta_meses               :integer
#  msi                       :boolean          default(FALSE), not null
#  requires_authorization    :boolean          default(FALSE), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  quote_development_rule_id :bigint           not null
#
# Indexes
#
#  index_quote_dev_rule_tiers_on_rule_id                  (quote_development_rule_id)
#  index_quote_dev_rule_tiers_on_rule_id_and_hasta_meses  (quote_development_rule_id,hasta_meses) UNIQUE
#
# Un tramo de una QuoteDevelopmentRule: `hasta_meses` nil significa "sin límite superior" (el
# tramo que atrapa todo lo que no cayó en un tramo anterior). Ver QuoteDevelopmentRule#tier_for.
class QuoteDevelopmentRuleTier < ApplicationRecord
  belongs_to :quote_development_rule

  validates :hasta_meses, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
end
