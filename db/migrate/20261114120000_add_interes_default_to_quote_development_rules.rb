# Tasa de interés anual por defecto (en %) con la que se cotiza un desarrollo — reemplaza el 8%
# fijo en código. nil = el desarrollo no tiene una tasa propia y se usa
# QuoteDevelopmentRule::FALLBACK_INTERES. Ver QuoteDevelopmentRule.default_interes_for.
class AddInteresDefaultToQuoteDevelopmentRules < ActiveRecord::Migration[7.1]
  def change
    add_column :quote_development_rules, :interes_default, :decimal, precision: 5, scale: 2
  end
end
