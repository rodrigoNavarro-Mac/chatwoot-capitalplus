namespace :chatwoot do
  desc 'Re-resuelve el revenue_contact_id de deals ya vinculados a su lead — corrige los que ' \
       'quedaron anclados a un RevenueContact vacío (sin teléfono/correo) porque su resolve_for_deal ' \
       'corrió ANTES de que existiera el vínculo revenue_lead_id (ver el fix en ' \
       'SyncZohoLeadsJob#link_converted_deal, que ya lo hace solo de aquí en adelante).' \
       "\nUso: ACCOUNT_ID=2 bin/rails chatwoot:fix_deal_contacts"
  task fix_deal_contacts: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    resolver = RevenueIntelligence::IdentityResolver.new(account)
    fixed = 0
    total = 0

    account.revenue_deals.where.not(revenue_lead_id: nil).includes(:revenue_contact, :revenue_lead).find_each do |deal|
      total += 1
      before = deal.revenue_contact_id
      resolver.resolve_for_deal(deal)
      fixed += 1 if deal.revenue_contact_id != before
    end

    with_email = account.revenue_deals.where.not(revenue_lead_id: nil).joins(:revenue_contact)
                        .where.not(revenue_contacts: { email: nil }).count

    puts "#{total} deals revisados, #{fixed} re-apuntados a otro contacto (cuenta #{account.id})."
    puts "Deals vinculados con correo resuelto ahora: #{with_email}/#{total}."
  end
end
