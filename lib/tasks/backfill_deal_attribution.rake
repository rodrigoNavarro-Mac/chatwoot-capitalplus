namespace :chatwoot do
  desc 'Copia la atribución de Meta Ads (campaña/adset/advert/plataforma/etc.) del Lead al Deal ' \
       'para deals ya vinculados ANTES de que RevenueIntelligence::DealAttributionCopier ' \
       'existiera — de ahí en adelante se copia sola en el momento del vínculo (auto o manual).' \
       "\nUso: ACCOUNT_ID=2 bin/rails chatwoot:backfill_deal_attribution"
  task backfill_deal_attribution: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    count = 0

    account.revenue_deals.where.not(revenue_lead_id: nil).includes(:revenue_lead).find_each do |deal|
      next if deal.revenue_lead.blank?

      RevenueIntelligence::DealAttributionCopier.copy(deal: deal, lead: deal.revenue_lead)
      count += 1
    end

    puts "Atribución copiada/verificada en #{count} deals (cuenta #{account.id})."
  end
end
