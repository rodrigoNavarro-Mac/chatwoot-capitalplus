namespace :chatwoot do
  desc 'Corrige First_Contact_Time en Zoho para leads que lo tenian marcado por la plantilla de ' \
       'apertura de WhatsApp (fix ya desplegado en app/services/crm/zoho/processor_service.rb, ' \
       'pero no retroactivo) -- revisa el historial real de mensajes en Chatwoot de cada lead y ' \
       'deja First_Contact_Time en el timestamp del primer mensaje humano que NO sea plantilla, ' \
       'o en blanco si nunca lo hubo.' \
       "\nPor default solo IMPRIME lo que cambiaria (dry run), no escribe nada en Zoho." \
       "\nUso: ACCOUNT_ID=2 DESARROLLO=Fuego bin/rails chatwoot:backfill_first_contact_time" \
       "\nAgregar DRY_RUN=false para aplicar de verdad. DESARROLLO es opcional (sin el, revisa " \
       'todos los leads de la cuenta).'
  task backfill_first_contact_time: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    desarrollo = ENV.fetch('DESARROLLO', nil)
    dry_run = ENV.fetch('DRY_RUN', 'true') != 'false'
    hook = account.hooks.find_by(app_id: 'zoho_crm', status: 'enabled')
    raise "No hay hook de Zoho CRM habilitado para la cuenta #{account.id}" if hook.blank?

    leads_client = Crm::Zoho::Api::LeadsClient.new(hook)

    real_first_contact_time = lambda do |chatwoot_contact_id|
      Message.joins(:conversation)
             .where(conversations: { contact_id: chatwoot_contact_id, account_id: account.id })
             .outgoing.where.not(sender_type: %w[AgentBot Captain::Assistant]).where.not(private: true)
             .where("(messages.additional_attributes->'campaign_id') is null")
             .where("(messages.content_attributes->'template_params') is null")
             .order(:created_at).limit(1).pick(:created_at)
    end

    scope = account.revenue_leads.where.not(revenue_contact_id: nil)
    scope = scope.where(desarrollo: desarrollo) if desarrollo.present?

    total = 0
    changed = 0
    skipped_zoho = 0

    scope.includes(:revenue_contact).find_each do |lead|
      total += 1
      chatwoot_contact_id = lead.revenue_contact&.chatwoot_contact_id
      next if chatwoot_contact_id.blank?

      real_time = real_first_contact_time.call(chatwoot_contact_id)
      next if real_time&.to_i == lead.first_contact_at&.to_i

      changed += 1
      puts "lead=#{lead.id} zoho_lead_id=#{lead.zoho_lead_id} actual=#{lead.first_contact_at&.iso8601 || 'blank'} " \
           "-> real=#{real_time&.iso8601 || 'blank'}"
      next if dry_run

      # Zoho rechaza cualquier update a un Lead ya convertido ("can't update the converted
      # record") -- confirmado en vivo. raw_payload['Converted_Deal'] localmente puede estar
      # desactualizado (el mismo problema ya documentado en SyncZohoMeetingsJob), asi que no se
      # predice antes -- se maneja el error real si ocurre. Para esos, solo se corrige la copia
      # local (que es lo que de verdad alimenta Revenue Intelligence); Zoho se queda
      # desactualizado ahi, limitacion de la plataforma, no nuestra.
      begin
        leads_client.update(lead.zoho_lead_id, { 'First_Contact_Time' => real_time&.iso8601 || '' })
      rescue Crm::Zoho::Api::BaseClient::ApiError => e
        skipped_zoho += 1
        puts "  (Zoho rechazo el update -- #{e.message} -- solo se corrigio localmente)"
      end
      lead.update!(first_contact_at: real_time)
    end

    puts "#{total} leads revisados, #{changed} con First_Contact_Time distinto al real (#{skipped_zoho} convertidos, " \
         'Zoho no se pudo tocar en esos).'
    puts 'DRY RUN -- no se escribio nada en Zoho ni local. Corre de nuevo con DRY_RUN=false para aplicar.' if dry_run
  end
end
