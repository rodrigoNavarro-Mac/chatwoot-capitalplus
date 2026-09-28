json.id @quote_development_rule.id
json.desarrollo @quote_development_rule.desarrollo
json.quote_development_rule_tiers @quote_development_rule.quote_development_rule_tiers do |tier|
  json.id tier.id
  json.hasta_meses tier.hasta_meses
  json.msi tier.msi
  json.requires_authorization tier.requires_authorization
end
