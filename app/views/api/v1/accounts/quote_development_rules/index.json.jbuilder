json.array! @quote_development_rules do |rule|
  json.id rule.id
  json.desarrollo rule.desarrollo
  json.quote_development_rule_tiers rule.quote_development_rule_tiers do |tier|
    json.id tier.id
    json.hasta_meses tier.hasta_meses
    json.msi tier.msi
    json.requires_authorization tier.requires_authorization
  end
end
