# Diagnostico puntual (sesion 2026-09-23/24): confirmar con el created_at del hook de
# Aircall (app_id: 'aircall') desde cuando existe cobertura real de llamadas -- ver
# Crm::Aircall::CallHistoryBackfillService, que se detiene solo en cuanto un mes no
# devuelve llamadas en Aircall (o sea, el historial de Aircall mismo no llega mas atras).
# rubocop:disable Rails/Output
account = Account.find(2)

hook = account.hooks.find_by(app_id: 'aircall')
if hook.blank?
  puts 'no hay hook de aircall en esta cuenta'
else
  puts "hook aircall id=#{hook.id} status=#{hook.status}"
  puts "hook created_at=#{hook.created_at}"
  puts "hook updated_at=#{hook.updated_at}"
end

puts '---'
puts "primera llamada registrada: #{Call.joins(:inbox).where(inboxes: { account_id: account.id }).minimum(:started_at)}"
pre_aircall_leads = account.revenue_leads.where('created_at_source < ?', Date.new(2026, 8, 1))
puts "leads con created_at_source antes del 2026-08-01: #{pre_aircall_leads.count}"
puts "de esos, con first_call_attempt_at ya poblado: #{pre_aircall_leads.where.not(first_call_attempt_at: nil).count}"
# rubocop:enable Rails/Output
