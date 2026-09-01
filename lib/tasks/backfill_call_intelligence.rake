namespace :chatwoot do
  desc 'Encola el análisis de llamadas (Crm::Aircall::CallIntelligenceBackfillService) para ' \
       'llamadas de Aircall ya completadas en un rango de fechas que todavía no tienen análisis — ' \
       'idempotente, nunca duplica ni reprocesa las que ya tienen call_analysis.' \
       "\nPor default solo IMPRIME cuántas llamadas entrarían (dry run) — no gasta nada. Cada " \
       'llamada encolada de verdad consume créditos de OpenAI (Whisper + el análisis LLM) y, si ' \
       'tiene deal vinculado en Zoho, puede generar una Nota ahí (salvo confidence baja).' \
       "\nUso: ACCOUNT_ID=2 FROM=2026-08-01 TO=2026-08-31 bin/rails chatwoot:backfill_call_intelligence" \
       "\nAgregar DRY_RUN=false para encolar de verdad. TO es opcional (default: ahora)."
  task backfill_call_intelligence: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    raise "No hay hook de Aircall habilitado para la cuenta #{account.id}" if account.hooks.find_by(app_id: 'aircall', status: 'enabled').blank?
    raise "call_intelligence no está activo (feature flag o créditos) para la cuenta #{account.id}" unless CallAnalysis.available_for?(account)

    from = Time.zone.parse(ENV.fetch('FROM'))
    to = ENV['TO'].present? ? Time.zone.parse(ENV['TO']).end_of_day : Time.current
    service = Crm::Aircall::CallIntelligenceBackfillService.new(account: account, from: from, to: to)

    puts "#{service.pending_calls.count} llamadas completadas sin analizar entre #{from} y #{to} (cuenta #{account.id})."

    if ENV.fetch('DRY_RUN', 'true') != 'false'
      puts 'DRY RUN — no se encoló nada. Corre de nuevo con DRY_RUN=false para encolar el análisis real.'
      next
    end

    queued = service.perform!
    puts "Encoladas #{queued} llamadas — el análisis corre en segundo plano (Sidekiq). Revisa " \
         'CallAnalysis.needs_review o la cola de revisión del dashboard en unos minutos.'
  end
end
