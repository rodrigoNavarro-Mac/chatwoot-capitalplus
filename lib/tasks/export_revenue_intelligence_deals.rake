require 'csv'

namespace :chatwoot do
  desc 'Exporta a CSV todos los Deals de un desarrollo — nombre, correo, celular, etapa, monto y ' \
       'UTMs de Meta Ads. Imprime además un diagnóstico de cuántos deals tienen contacto resuelto ' \
       'y cuántos de esos traen correo/celular, para investigar huecos de identidad.' \
       "\nUso: ACCOUNT_ID=2 DESARROLLO=Fuego bin/rails chatwoot:export_deals"
  task export_deals: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    desarrollo = ENV.fetch('DESARROLLO')
    output = ENV.fetch('OUTPUT', "/app/storage/deals_#{desarrollo.parameterize}.csv")

    deals = account.revenue_deals.where(desarrollo: desarrollo).includes(:revenue_contact, :revenue_lead)
    with_contact = 0
    with_email = 0
    with_phone = 0

    rows = deals.map do |deal|
      contact = deal.revenue_contact || deal.revenue_lead&.revenue_contact
      with_contact += 1 if contact
      with_email += 1 if contact&.email.present?
      with_phone += 1 if contact&.raw_phone.present?

      {
        nombre: (deal.raw_payload || {})['Deal_Name'],
        correo: contact&.email,
        celular: contact&.raw_phone,
        etapa: deal.stage,
        monto: deal.amount,
        fecha_creacion: deal.created_at_source&.in_time_zone('America/Cancun')&.strftime('%Y-%m-%d'),
        campaign: deal.campaign_name,
        adset: deal.adset_name,
        advert: deal.advert_name,
        platform: deal.platform
      }
    end

    # BOM al inicio: sin él, Excel en Windows reinterpreta el UTF-8 como Windows-1252.
    File.write(output, "\xEF\xBB\xBF")
    CSV.open(output, 'a') do |csv|
      csv << %w[nombre correo celular etapa monto fecha_creacion campaign adset advert platform]
      rows.each { |r| csv << r.values }
    end

    puts "#{rows.size} deals escritos en #{output} (cuenta #{account.id}, desarrollo #{desarrollo})."
    puts "Con contacto resuelto: #{with_contact}/#{rows.size} — de esos, con correo: #{with_email}, con celular: #{with_phone}."
  end
end
