class MigrateWhatsappCadencesFlagToExt1 < ActiveRecord::Migration[7.1]
  OLD_BIT = 1 << 49 # posicion 50 (1-indexed) en feature_flags, antes del merge con v4.16.1

  def up
    # whatsapp_cadences vivia en feature_flags (bit 50). El merge con Chatwoot v4.16.1 llevo
    # esa columna a 64 features (limite: 63) y sus posiciones estan fijadas por sus propios
    # specs (ver account_spec.rb), asi que la movimos a feature_flags_ext_1. Trasladamos el
    # bit para no perder el flag en cuentas que ya lo tenian activo (Capital Plus, produccion,
    # entre ellas), usando el bit crudo viejo porque el nombre "whatsapp_cadences" en
    # feature_flags ya no existe en el config actual.
    Account.where('feature_flags & ? != 0', OLD_BIT).find_each(batch_size: 100) do |account|
      account.update_column(:feature_flags, account.feature_flags & ~OLD_BIT)
      account.enable_features(:whatsapp_cadences)
      account.save!(validate: false)
    end
  end

  def down
    Account.feature_whatsapp_cadences.find_each(batch_size: 100) do |account|
      account.update_column(:feature_flags, account.feature_flags | OLD_BIT)
      account.disable_features(:whatsapp_cadences)
      account.save!(validate: false)
    end
  end
end
