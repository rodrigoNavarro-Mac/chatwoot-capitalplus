# Convierte el umbral único preexistente (msi_auto_max_plazo) en su equivalente de 2 tramos antes
# de eliminar la columna: [0..umbral] MSI sin autorización, [umbral+1..sin límite] con
# autorización y sin MSI — el mismo comportamiento que tenía la regla anterior.
# rubocop:disable Style/OneClassPerFile -- clases sombra de solo lectura/escritura para la migración de datos
class MigrateMsiAutoMaxPlazoToTiers < ActiveRecord::Migration[7.1]
  class QuoteDevelopmentRule < ActiveRecord::Base
    self.table_name = 'quote_development_rules'
  end

  class QuoteDevelopmentRuleTier < ActiveRecord::Base
    self.table_name = 'quote_development_rule_tiers'
  end

  def up
    QuoteDevelopmentRule.reset_column_information
    QuoteDevelopmentRule.find_each do |rule|
      QuoteDevelopmentRuleTier.create!(
        quote_development_rule_id: rule.id, hasta_meses: rule.msi_auto_max_plazo, msi: true, requires_authorization: false
      )
      QuoteDevelopmentRuleTier.create!(
        quote_development_rule_id: rule.id, hasta_meses: nil, msi: false, requires_authorization: true
      )
    end

    remove_column :quote_development_rules, :msi_auto_max_plazo, :integer
  end

  def down
    add_column :quote_development_rules, :msi_auto_max_plazo, :integer

    QuoteDevelopmentRule.reset_column_information
    QuoteDevelopmentRule.find_each do |rule|
      tier = QuoteDevelopmentRuleTier.where(quote_development_rule_id: rule.id, msi: true).first
      rule.update!(msi_auto_max_plazo: tier&.hasta_meses || 0)
    end

    change_column_null :quote_development_rules, :msi_auto_max_plazo, false
    QuoteDevelopmentRuleTier.where(quote_development_rule_id: QuoteDevelopmentRule.select(:id)).delete_all
  end
end
# rubocop:enable Style/OneClassPerFile
