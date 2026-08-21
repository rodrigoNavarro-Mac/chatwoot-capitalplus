namespace :chatwoot do
  desc 'Vuelve a correr el backfill histórico de Aircall (Crm::Aircall::CallHistoryBackfillService) para ' \
       'recuperar llamadas que nunca se registraron por el bug de multi-línea (find_conversation no ' \
       'encontraba la conversación en el inbox correcto, ej. capitalplus) — el servicio ya es idempotente ' \
       'por provider_call_id, así que no toca ni re-crea llamadas que ya se sincronizaron (aunque hayan ' \
       'quedado en el inbox equivocado), solo crea las que faltaban. Correr una sola vez tras el fix.'
  task backfill_missed_aircall_calls: :environment do
    account_id = ENV.fetch('ACCOUNT_ID', nil)
    scope = account_id ? Account.where(id: account_id) : Account.all

    scope.find_each do |account|
      hook = account.hooks.find_by(app_id: 'aircall', status: 'enabled')
      next if hook.blank?

      before_count = Call.where(account_id: account.id, provider: :aircall).count
      processed = Crm::Aircall::CallHistoryBackfillService.new(account).perform
      after_count = Call.where(account_id: account.id, provider: :aircall).count

      puts "Cuenta #{account.id} (#{account.name}): #{processed} llamadas revisadas del historial, " \
           "#{after_count - before_count} nuevas recuperadas"
    rescue StandardError => e
      puts "Error en cuenta #{account.id}: #{e.message}"
    end

    puts 'Backfill completado.'
  end
end
