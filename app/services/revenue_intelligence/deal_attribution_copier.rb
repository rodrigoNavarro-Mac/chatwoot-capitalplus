# Copia el set de atribución de Meta Ads (campaña/adset/advert/plataforma/etc.) del Lead al Deal
# en el momento en que se vinculan. Zoho nunca guarda estos campos en el propio Deal (confirmado
# vía Zoho CRM API getFields: el módulo Deals solo trae Lead_Source/Campaign_Source) — sin esta
# copia, la atribución se pierde para siempre en cuanto el Lead se convierte, si el vínculo
# revenue_lead_id llegara a romperse después o el Lead se purgara en Zoho.
#
# Conservador, mismo principio que RevenueIntelligence::IdentityResolver: solo llena columnas del
# Deal que están en blanco, nunca sobrescribe un valor ya presente.
class RevenueIntelligence::DealAttributionCopier
  ATTRIBUTES = %i[campaign_id campaign_name adset_id adset_name advert_id advert_name
                  ad_account_id ad_account_name form_id form_name page_id page_name
                  social_lead_id lead_type platform qualification_channel].freeze

  def self.copy(deal:, lead:)
    new(deal: deal, lead: lead).copy
  end

  def initialize(deal:, lead:)
    @deal = deal
    @lead = lead
  end

  def copy
    updates = ATTRIBUTES.index_with { |attribute| deal[attribute].presence || lead[attribute] }
    changed = updates.any? { |attribute, value| value != deal[attribute] }
    deal.update!(updates) if changed
  end

  private

  attr_reader :deal, :lead
end
