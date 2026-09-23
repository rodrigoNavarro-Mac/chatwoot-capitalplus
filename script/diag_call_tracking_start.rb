# Diagnóstico puntual (sesión 2026-09-23): confirmar si el tracking de llamadas
# (Aircall/Chatwoot Call) tiene una fecha de arranque real, lo cual explicaría el
# cluster de 7 leads de finales de julio cuya "primera llamada" quedó registrada
# toda el mismo dia (2026-08-05) -- ver script/diag_call_sla.rb.
# rubocop:disable Rails/Output
account = Account.find(2)

first_call_ever = Call.joins(:inbox).where(inboxes: { account_id: account.id }).order(started_at: :asc).first
puts "primera llamada jamas registrada: id=#{first_call_ever&.id} started_at=#{first_call_ever&.started_at}"
puts "direction=#{first_call_ever&.direction}"

total_calls = Call.joins(:inbox).where(inboxes: { account_id: account.id }).count
puts "total de llamadas registradas: #{total_calls}"

by_day = Call.joins(:inbox).where(inboxes: { account_id: account.id })
             .where(started_at: Date.new(2026, 8, 1)..Date.new(2026, 8, 10).end_of_day)
             .group('date(started_at)').count.sort.to_h
puts "llamadas por dia (1-10 agosto 2026): #{by_day}"

puts '---'
puts 'calls con id 1 al 10:'
Call.where(id: 1..10).order(:id).each do |c|
  puts "id=#{c.id} started_at=#{c.started_at} direction=#{c.direction} contact_id=#{c.contact_id} inbox=#{c.inbox_id}"
end
# rubocop:enable Rails/Output
