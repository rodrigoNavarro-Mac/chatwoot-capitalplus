namespace :chatwoot do
  desc 'Sincroniza el histórico de Zoho Leads/Deals/Stage_History/Meetings hacia las tablas ' \
       'revenue_* (Revenue Intelligence, Fase 1) para una cuenta, desde una fecha dada — ' \
       'idempotente: reusa los mismos RevenueIntelligence::SyncZoho*Job del cron (vía sus ' \
       'cursores propios) en vez de duplicar la lógica de sincronización.' \
       "\nPor default solo IMPRIME un conteo aproximado (dry run) — no importa nada." \
       "\nUso: ACCOUNT_ID=2 FROM=2025-08-01 bin/rails chatwoot:backfill_revenue_intelligence" \
       "\nAgregar DRY_RUN=false para sincronizar de verdad. Si el rango trae más registros de los " \
       'que un job procesa en una sola corrida, correr la tarea de nuevo avanza desde donde quedó ' \
       'el cursor persistente — no hace falta borrar nada entre corridas.'
  task backfill_revenue_intelligence: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    raise "No hay hook de Zoho CRM habilitado para la cuenta #{account.id}" if account.hooks.find_by(app_id: 'zoho_crm', status: 'enabled').blank?

    from = Time.zone.parse(ENV.fetch('FROM'))
    service = RevenueIntelligence::BackfillService.new(account: account, from: from)

    counts = service.preview_counts
    puts "Leads modificados desde #{from}: #{counts[:leads]}. Deals modificados desde #{from}: #{counts[:deals]} (cuenta #{account.id})."

    if ENV.fetch('DRY_RUN', 'true') != 'false'
      puts 'DRY RUN — no se sincronizó nada. Corre de nuevo con DRY_RUN=false para importar de verdad.'
      next
    end

    service.perform!
    puts "Backfill completo (cuenta #{account.id}): revenue_leads=#{account.revenue_leads.count} " \
         "revenue_deals=#{account.revenue_deals.count} revenue_stage_events=#{account.revenue_stage_events.count} " \
         "revenue_appointments=#{account.revenue_appointments.count} revenue_contacts=#{account.revenue_contacts.count}."
  end
end
