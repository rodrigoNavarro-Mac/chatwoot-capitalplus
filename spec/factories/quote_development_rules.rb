FactoryBot.define do
  factory :quote_development_rule do
    account
    sequence(:desarrollo) { |n| "Desarrollo #{n}" }

    # QuoteDevelopmentRule#validate requires at least one tier, así que por defecto arma un tramo
    # "sin límite" — pasar `quote_development_rule_tiers_attributes:` como override para tramos
    # específicos en vez de usar la factory :quote_development_rule_tier por separado.
    quote_development_rule_tiers_attributes do
      [{ hasta_meses: nil, msi: false, requires_authorization: false }]
    end
  end

  factory :quote_development_rule_tier do
    quote_development_rule
    hasta_meses { 12 }
    msi { false }
    requires_authorization { false }
  end
end
