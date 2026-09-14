# Resuelve a qué "desarrollo" pertenece un evento/lead/deal: prioridad deal > lead > '_all' — un
# deal puede tener su propio desarrollo distinto al del lead que lo originó (ver DealMapper), y no
# todo evento trae ambos ids. Compartido entre RefreshAggregatesJob (rollups) y
# debug_funnel_leads.rake (diagnóstico) para que nunca diverjan.
module RevenueIntelligence::DesarrolloResolver
  module_function

  def lookups(account)
    {
      lead: account.revenue_leads.pluck(:zoho_lead_id, :desarrollo).to_h,
      deal: account.revenue_deals.pluck(:zoho_deal_id, :desarrollo).to_h
    }
  end

  def resolve(lookups, zoho_lead_id: nil, zoho_deal_id: nil)
    lookups[:deal][zoho_deal_id] || lookups[:lead][zoho_lead_id] || '_all'
  end
end
