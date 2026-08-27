class EnsureWhatsappCadencesFeatureEnabled < ActiveRecord::Migration[7.1]
  # Red de seguridad para MigrateWhatsappCadencesFlagToExt1: si esa migracion no llego a
  # correr en produccion (o corrio antes de que el bit viejo quedara seteado), esta se
  # asegura de que whatsapp_cadences quede activo de todos modos. Instalacion self-hosted
  # de un solo cliente (Capital Plus), asi que activarlo para todas las cuentas es seguro.
  def up
    Account.find_each(batch_size: 100) do |account|
      next if account.feature_enabled?(:whatsapp_cadences)

      account.enable_features(:whatsapp_cadences)
      account.save!(validate: false)
    end
  end

  def down
    Account.feature_whatsapp_cadences.find_each(batch_size: 100) do |account|
      account.disable_features(:whatsapp_cadences)
      account.save!(validate: false)
    end
  end
end
