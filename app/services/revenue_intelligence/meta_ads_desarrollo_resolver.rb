# Resuelve a qué desarrollo pertenece una campaña de Meta Ads, por nombre. Necesario porque una
# sola cuenta publicitaria de Meta puede correr campañas de VARIOS desarrollos a la vez
# (confirmado en producción, sesión 2026-09-23: la cuenta "Fuego Cancún" trae también campañas de
# Amura y P. Quintana Roo) -- no se puede asumir un desarrollo fijo por Hook/cuenta.
#
# A diferencia de RevenueIntelligence::DesarrolloResolver (que resuelve por zoho_lead_id/
# zoho_deal_id, usando el campo Desarrollo ya sincronizado de Zoho), aquí no hay ningún id de
# Zoho -- solo el nombre de campaña que Meta reporta -- así que el match es por palabra clave.
#
# ALIASES mapea desarrollo -> palabra clave a buscar (case-insensitive) en el nombre de campaña.
# Confirmado con el usuario, no inventado: solo se listan los desarrollos cuya palabra clave ya se
# verificó contra nombres de campaña reales. Un desarrollo sin entrada aquí simplemente no se
# resuelve (desarrollo: nil, visible como "sin dato" en vez de asignado incorrectamente) hasta que
# se confirme su palabra clave cuando aparezca.
module RevenueIntelligence::MetaAdsDesarrolloResolver
  ALIASES = {
    'Fuego' => 'fuego',
    'Amura' => 'amura',
    'P. Quintana Roo' => 'quintana roo'
  }.freeze

  module_function

  def resolve(campaign_name)
    return nil if campaign_name.blank?

    normalized = campaign_name.downcase
    match = ALIASES.find { |_desarrollo, keyword| normalized.include?(keyword) }
    match&.first
  end
end
