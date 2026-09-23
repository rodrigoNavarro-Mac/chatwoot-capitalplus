# Diagnostico puntual (sesion 2026-09-23): confirmar la fecha de creacion/activacion
# del inbox de llamadas (inbox_id=1 segun diag_call_tracking_start.rb) para tener una
# fecha objetiva de "arranque del tracking de llamadas", en vez de adivinar por volumen.
# rubocop:disable Rails/Output
account = Account.find(2)

Inbox.where(account_id: account.id).find_each do |inbox|
  next if Call.where(inbox_id: inbox.id).none?

  puts "inbox id=#{inbox.id} name=#{inbox.name} channel_type=#{inbox.channel_type}"
  puts "inbox created_at=#{inbox.created_at}"
  channel = inbox.channel
  puts "channel created_at=#{channel&.created_at}" if channel.respond_to?(:created_at)
  puts "llamadas en este inbox=#{Call.where(inbox_id: inbox.id).count}"
  puts '---'
end
# rubocop:enable Rails/Output
