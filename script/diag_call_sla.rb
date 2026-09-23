# Diagnóstico puntual (sesión 2026-09-23): investigar si los tiempos altos de
# "tiempo hasta el primer intento de llamada" (marketing_call_sla) son reales o un
# artefacto de datos -- en particular, si un lead está heredando la primera llamada
# saliente de OTRO ciclo de lead que comparte el mismo RevenueContact/chatwoot_contact_id
# (ver RevenueIntelligence::CalculateSetterResponseTimeJob#process_call_attempt).
#
# Salida deliberadamente por STDOUT (no Rails.logger): en producción log_level es
# 'info', así que Rails.logger.debug quedaría silenciado y este script perdería su
# propósito de mostrar el resultado en consola al correrlo con rails runner.
# rubocop:disable Rails/Output
#
# Uso: bundle exec rails runner script/diag_call_sla.rb
account = Account.find(2)

leads = account.revenue_leads
               .where.not(first_call_attempt_business_seconds: nil)
               .where('first_call_attempt_seconds <= ?', 7.days.to_i)
               .order(first_call_attempt_business_seconds: :desc)
               .limit(15)

leads.each do |lead|
  puts '-----'
  puts "zoho_lead_id=#{lead.zoho_lead_id}"
  puts "created_at_source=#{lead.created_at_source}"
  puts "first_call_attempt_at=#{lead.first_call_attempt_at}"
  business_min = (lead.first_call_attempt_business_seconds / 60.0).round(1)
  clock_min = (lead.first_call_attempt_seconds / 60.0).round(1)
  puts "business_min=#{business_min} clock_min=#{clock_min}"
  contact = lead.revenue_contact
  puts "chatwoot_contact_id=#{contact&.chatwoot_contact_id}"
  other_leads = account.revenue_leads.where(revenue_contact_id: lead.revenue_contact_id).count
  puts "otros_leads_mismo_contacto=#{other_leads}" if other_leads > 1
  first_call_ever = Call.where(contact_id: contact&.chatwoot_contact_id, direction: Call.directions['outgoing']).order(started_at: :asc).first
  puts "primera_llamada_saliente_alguna_vez=#{first_call_ever&.started_at}"
  puts "primera_llamada_id=#{first_call_ever&.id} inbox=#{first_call_ever&.inbox_id}"
end

puts '==='
avg_top15 = (leads.sum(&:first_call_attempt_business_seconds) / 60.0 / leads.size).round(1)
puts "Resumen: promedio del top 15 en minutos habiles = #{avg_top15}"
# rubocop:enable Rails/Output
