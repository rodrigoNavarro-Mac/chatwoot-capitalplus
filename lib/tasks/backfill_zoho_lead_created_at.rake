namespace :chatwoot do
  desc 'Corre Crm::Zoho::LeadCreatedAtBackfillService para cachear el Created_Time real de Zoho ' \
       '(zoho_created_at) en los contactos que ya tienen zoho_id vinculado pero no lo tienen — ' \
       'necesario para que el embudo de ventas (V2::Reports::SalesFunnelBuilder) distinga leads ' \
       'nuevos de leads reactivados. Idempotente, se puede volver a correr para reintentar los que ' \
       'fallaron.' \
       "\nPor default solo IMPRIME cuántos contactos entrarían (dry run) — no gasta nada. Cada " \
       'contacto real consume 1 llamada a la API de Zoho.' \
       "\nUso: ACCOUNT_ID=2 bin/rails chatwoot:backfill_zoho_lead_created_at" \
       "\nAgregar DRY_RUN=false para escribir de verdad. ACCOUNT_ID es opcional (default: todas " \
       'las cuentas con integración de Zoho CRM habilitada).'
  task backfill_zoho_lead_created_at: :environment do
    dry_run = ENV.fetch('DRY_RUN', 'true') != 'false'

    zoho_crm_accounts.find_each { |account| backfill_zoho_lead_created_at_for(account, dry_run: dry_run) }

    puts(dry_run ? 'DRY RUN — no se escribió nada. Corre de nuevo con DRY_RUN=false para backfillear de verdad.' : 'Backfill completado.')
  end
end

def zoho_crm_accounts
  return Account.where(id: ENV.fetch('ACCOUNT_ID')) if ENV['ACCOUNT_ID'].present?

  Account.joins(:hooks).where(hooks: { app_id: 'zoho_crm', status: 'enabled' }).distinct
end

def backfill_zoho_lead_created_at_for(account, dry_run:)
  service = Crm::Zoho::LeadCreatedAtBackfillService.new(account)
  pending_count = service.pending_contacts.count
  return if pending_count.zero?

  puts "Cuenta #{account.id} (#{account.name}): #{pending_count} contactos sin zoho_created_at."
  return if dry_run

  stats = service.perform
  puts "Cuenta #{account.id}: #{stats[:updated]} actualizados (#{stats[:relinked]} re-vinculados a " \
       "un zoho_id vigente), #{stats[:not_found]} sin registro en Zoho, #{stats[:errored]} con " \
       'error de API (reintentables corriendo de nuevo).'
rescue StandardError => e
  puts "Error en cuenta #{account.id}: #{e.message}"
end
