namespace :chatwoot do
  desc 'Refresca revenue_leads.lead_source contra el valor ACTUAL en Zoho para toda la cuenta -- ' \
       'confirmado un desfase masivo en producción (2026-09-10): 2477 de 3083 leads locales decían ' \
       '"Meta Ads" cuando Zoho ya los tiene como "Facebook Ads" (un rename del picklist en Zoho no ' \
       'bumpea Modified_Time por lead, así que la sincronización incremental normal nunca lo detecta).' \
       "\nPor default solo IMPRIME lo que cambiaría (dry run), no escribe nada." \
       "\nUso: ACCOUNT_ID=2 bin/rails chatwoot:refresh_lead_source" \
       "\nAgregar DRY_RUN=false para aplicar de verdad. Correr chatwoot:recompute_rollups después -- " \
       'los rollups de campaign/lead_source ya acumulados usan el lead_source viejo como dimension_id.'
  task refresh_lead_source: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    dry_run = ENV.fetch('DRY_RUN', 'true') != 'false'
    hook = account.hooks.find_by(app_id: 'zoho_crm', status: 'enabled')
    raise "No hay hook de Zoho CRM habilitado para la cuenta #{account.id}" if hook.blank?

    client = Crm::Zoho::Api::LeadsClient.new(hook)
    fetch_current_sources = lambda do |batch|
      ids = batch.map { |_, zoho_id, _| zoho_id }
      result = client.search_by_criteria("(id:in:#{ids.join(',')})", per_page: ids.size, converted: 'both')
      result[:data].to_h { |record| [record['id'], record['Lead_Source']] }
    end

    leads = account.revenue_leads.pluck(:id, :zoho_lead_id, :lead_source)
    changed = 0

    leads.each_slice(50) do |batch|
      current_by_zoho_id = fetch_current_sources.call(batch)

      batch.each do |local_id, zoho_id, local_source|
        current_source = current_by_zoho_id[zoho_id]
        next if current_source.nil? || current_source == local_source

        changed += 1
        puts "lead #{zoho_id}: #{local_source.inspect} -> #{current_source.inspect}"
        # rubocop:disable Rails/SkipsModelValidations
        account.revenue_leads.where(id: local_id).update_all(lead_source: current_source) unless dry_run
        # rubocop:enable Rails/SkipsModelValidations
      end
    end

    puts "#{leads.size} leads revisados, #{changed} con lead_source distinto al real de Zoho."
    puts 'DRY RUN -- no se escribió nada. Corre de nuevo con DRY_RUN=false para aplicar.' if dry_run
  end
end
