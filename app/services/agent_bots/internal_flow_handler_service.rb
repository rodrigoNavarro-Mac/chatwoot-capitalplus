class AgentBots::InternalFlowHandlerService
  def initialize(agent_bot, conversation, message_or_content)
    @agent_bot = agent_bot
    @conversation = conversation
    if message_or_content.is_a?(Message)
      @message = message_or_content
      @message_content_raw = message_or_content.content.to_s.strip
    else
      @message = nil
      @message_content_raw = message_or_content.to_s.strip
    end
    @message_content = @message_content_raw.downcase
    @config = agent_bot.bot_config.with_indifferent_access
    @variables = @config[:variables] || {}
  end

  def perform
    unless processable?
      Rails.logger.info("[InternalFlow] Conv ##{@conversation.id} — no processable")
      hand_off_to_agent_if_business_hours
      return
    end

    if in_collection_mode?
      process_collection_message
      return
    end

    current_step_name = @conversation.custom_attributes['_bot_current_step']
    Rails.logger.info("[InternalFlow] Conv ##{@conversation.id} step=#{current_step_name.inspect} msg=#{@message_content.truncate(40).inspect}")

    if current_step_name.blank?
      if provider_check_enabled? && !authorized_provider?
        unauthorized_msg = @config[:unauthorized_message].presence || 'Lo sentimos, no estás autorizado para usar este servicio.'
        send_bot_message(unauthorized_msg)
        @conversation.resolved!
        Rails.logger.info("[InternalFlow] Conv ##{@conversation.id} — unauthorized provider #{@conversation.contact.phone_number.inspect}")
        return
      end

      send_initial_step
      return
    end

    navigate_from(current_step_name)
  end

  private

  # ── Business hours hand-off ────────────────────────────────────────────────

  def hand_off_to_agent_if_business_hours
    inbox = @conversation.inbox
    return unless inbox.working_hours_enabled? && !inbox.out_of_office?
    return if @conversation.open?

    business_hours_message = @config.dig(:business_hours, :message).presence ||
                             'Hola, estamos en horario de atención. Un asesor te atenderá en breve.'
    send_bot_message(business_hours_message)
    @conversation.open!
    Rails.logger.info("[InternalFlow] Conv ##{@conversation.id} — business hours, handed off to agent")
  end

  # ── Provider authorization ─────────────────────────────────────────────────

  def provider_check_enabled?
    @config[:authorized_providers].present?
  end

  def authorized_provider?
    phone = @conversation.contact.phone_number.to_s.strip
    Array(@config[:authorized_providers]).map { |n| n.to_s.strip }.include?(phone)
  end

  # ── Collection mode ────────────────────────────────────────────────────────

  def in_collection_mode?
    @conversation.custom_attributes['_bot_collecting'] == true
  end

  def exit_keyword?
    @message_content.gsub(/\s+/, '') == 'salida()'
  end

  def process_collection_message
    if exit_keyword?
      finish_collection
      return
    end

    attachment_ids = @message&.attachments&.pluck(:id) || []
    entry = {
      'timestamp' => Time.current.iso8601,
      'content' => @message_content_raw,
      'attachment_ids' => attachment_ids
    }

    existing = @conversation.custom_attributes['_collection_entries'] || []
    updated_attrs = @conversation.custom_attributes.merge('_collection_entries' => existing + [entry])
    @conversation.update!(custom_attributes: updated_attrs)

    confirmation = attachment_ids.any? ? '✓ Foto registrada' : '✓ Registrado'
    send_bot_message(confirmation)
    Rails.logger.info("[InternalFlow] Conv ##{@conversation.id} — collected entry (attachments: #{attachment_ids.size})")
  end

  def finish_collection
    @conversation.reload
    Rails.logger.info("[InternalFlow] Conv ##{@conversation.id} — finishing collection")

    report = AgentBots::MaintenanceReportService.new(@conversation, @config).generate

    if report
      send_bot_message('⏳ Generando reporte, por favor espera...')
      distribute_report(report)
    else
      send_bot_message('⚠️ No hay información suficiente para generar el reporte.')
    end

    clean_attrs = @conversation.custom_attributes.reject do |k, _|
      %w[_bot_collecting _collection_start _collection_entries].include?(k.to_s)
    end
    @conversation.update!(custom_attributes: clean_attrs)
    @conversation.resolved!
  end

  def distribute_report(report)
    recipients = Array(@config[:report_recipients])
    if recipients.empty?
      Rails.logger.warn("[InternalFlow] Conv ##{@conversation.id} — no report_recipients configured")
      send_bot_message('✅ Reporte generado (sin destinatarios configurados).')
      return
    end

    development = @conversation.custom_attributes['_development'].presence || '—'
    date_str = Time.current.strftime('%d/%m/%Y %H:%M')

    recipients.each do |phone_number|
      send_report_to_number(phone_number, report, development, date_str)
    end

    send_bot_message("✅ Reporte enviado.\n📋 Desarrollo: #{development}\n📅 #{date_str}")
  end

  def send_report_to_number(phone_number, report, development, date_str)
    inbox = @conversation.inbox
    account = @conversation.account

    contact_inbox = ContactInboxWithContactBuilder.new(
      inbox: inbox,
      contact_attributes: { name: phone_number, phone_number: phone_number },
      source_id: phone_number.gsub(/\D/, '')
    ).perform

    target_conv = ConversationBuilder.new(
      params: { status: 'open' },
      contact_inbox: contact_inbox
    ).perform

    Messages::MessageBuilder.new(nil, target_conv, {
      content: report[:text_summary],
      private: false,
      message_type: 'outgoing',
      sender_type: 'AgentBot',
      sender_id: @agent_bot.id
    }).perform

    pdf_io = report[:pdf_io]
    if pdf_io
      pdf_io.rewind
      filename = "reporte_#{development.parameterize}_#{date_str.gsub(/[\/: ]/, '-')}.pdf"
      msg = target_conv.messages.build(
        account_id: account.id,
        inbox_id: inbox.id,
        message_type: 'outgoing',
        content: "📎 Reporte PDF — #{development} — #{date_str}",
        private: false,
        sender: @agent_bot
      )
      msg.attachments.build(
        account_id: account.id,
        file_type: :file,
        file: { io: pdf_io, filename: filename, content_type: 'application/pdf' }
      )
      msg.save!
    end

    Rails.logger.info("[InternalFlow] Report sent to #{phone_number} (conv ##{target_conv.id})")
  rescue StandardError => e
    Rails.logger.error("[InternalFlow] send_report_to_number #{phone_number} failed: #{e.message}")
  end

  def start_collection_mode
    updated_attrs = @conversation.custom_attributes.merge(
      '_bot_collecting' => true,
      '_collection_start' => Time.current.iso8601,
      '_collection_entries' => []
    )
    @conversation.update!(custom_attributes: updated_attrs)
    @conversation.open!
  end

  # ── Core flow ──────────────────────────────────────────────────────────────

  def send_initial_step
    step_name = determine_initial_step
    Rails.logger.info("[InternalFlow] send_initial_step → #{step_name.inspect}")
    step = @config.dig(:steps, step_name)
    unless step
      Rails.logger.warn("[InternalFlow] step '#{step_name}' not found in config")
      return
    end

    send_bot_message(step[:message])
    execute_action(step[:action])
    update_step(step_name)
    Rails.logger.info("[InternalFlow] initial step sent and step updated to #{step_name.inspect}")
  end

  def determine_initial_step
    if @conversation.custom_attributes.key?('_debug_zoho_found')
      zoho_found = @conversation.custom_attributes['_debug_zoho_found']
      clean = @conversation.custom_attributes.reject { |k, _| k.to_s == '_debug_zoho_found' }
      @conversation.update!(custom_attributes: clean)
      Rails.logger.info("[InternalFlow] debug override zoho_found=#{zoho_found}")
      if zoho_found
        enrich_from_zoho(fetch_zoho_record)
        return @config[:initial_step]
      else
        return @config.dig(:zoho_check, :not_found_initial_step).presence || @config[:initial_step]
      end
    end

    return @config[:initial_step] unless zoho_check_enabled?

    record = fetch_zoho_record
    if record
      enrich_from_zoho(record)
      @config[:initial_step]
    else
      @config.dig(:zoho_check, :not_found_initial_step).presence || @config[:initial_step]
    end
  end

  def navigate_from(current_step_name)
    step = @config.dig(:steps, current_step_name)
    return unless step

    capture_input(step[:capture], step[:capture_map]) if step[:capture].present?

    next_step_name = resolve_next_step(step)
    next_step = @config.dig(:steps, next_step_name)
    return unless next_step

    send_bot_message(next_step[:message])
    execute_action(next_step[:action])
    update_step(next_step_name)
  end

  def processable?
    return false if @conversation.inbox.channel_type != 'Channel::Whatsapp'
    return false if @config[:initial_step].blank?
    return false if @config[:steps].blank?
    return false if @conversation.open? && !in_collection_mode?
    inbox = @conversation.inbox
    return false if inbox.working_hours_enabled? && !inbox.out_of_office?

    true
  end

  def resolve_next_step(step)
    transitions = step[:transitions] || []
    matched = transitions.find { |t| transition_matches?(t[:when]) }
    matched ? matched[:next_step] : @config[:initial_step]
  end

  def transition_matches?(condition)
    condition = condition.with_indifferent_access

    return true if condition[:default]

    if condition[:contains].present?
      return condition[:contains].any? { |word| @message_content.include?(word.to_s.downcase) }
    end

    if condition[:equals].present?
      return @message_content == condition[:equals].to_s.downcase
    end

    if condition[:starts_with].present?
      return @message_content.start_with?(condition[:starts_with].to_s.downcase)
    end

    false
  end

  def send_bot_message(message_text)
    return if message_text.blank?

    interpolated = interpolate(message_text)
    params = { content: interpolated, private: false, message_type: 'outgoing',
               sender_type: 'AgentBot', sender_id: @agent_bot.id }
    result = Messages::MessageBuilder.new(nil, @conversation, params).perform
    Rails.logger.info("[InternalFlow] send_bot_message → msg ##{result&.id}")
    result
  end

  def execute_action(action)
    return if action.blank?

    case action.to_s
    when 'open_conversation'
      @conversation.open!
    when 'resolve_conversation'
      @conversation.resolved!
    when 'start_collection'
      start_collection_mode
    end
  end

  def update_step(step_name)
    updated_attrs = @conversation.custom_attributes.merge('_bot_current_step' => step_name)
    @conversation.update!(custom_attributes: updated_attrs)
  end

  def capture_input(key, capture_map = nil)
    value = resolve_capture_value(@message_content_raw, capture_map)
    @conversation.update!(custom_attributes: @conversation.custom_attributes.merge(key.to_s => value))
    sync_contact_name(value) if key.to_s == 'nombre'
    post_lead_note if key.to_s == 'plazo'
  end

  def resolve_capture_value(raw, capture_map)
    return raw if capture_map.blank?

    capture_map = capture_map.with_indifferent_access
    capture_map[raw.strip] || capture_map[raw.strip.downcase] || raw
  end

  def sync_contact_name(nombre)
    contact = @conversation.contact
    return if contact.name == nombre
    contact.update!(name: nombre)
    Rails.logger.info("[InternalFlow] contact ##{contact.id} name → #{nombre.inspect}")
  rescue StandardError => e
    Rails.logger.error("[InternalFlow] contact name update failed: #{e.message}")
  end

  def post_lead_note
    attrs  = @conversation.reload.custom_attributes
    nombre = attrs['nombre'].presence || '—'
    razon  = attrs['razon_compra'].presence || '—'
    plazo  = attrs['plazo'].presence || '—'

    content = "📋 *Datos del lead (capturado por bot):*\n• Nombre: #{nombre}\n• Razón de compra: #{razon}\n• Plazo de decisión: #{plazo}"
    Messages::MessageBuilder.new(nil, @conversation,
                                 content: content, private: true, message_type: 'outgoing',
                                 sender_type: 'AgentBot', sender_id: @agent_bot.id).perform
  rescue StandardError => e
    Rails.logger.error("[InternalFlow] post_lead_note failed: #{e.message}")
  end

  def interpolate(text)
    AgentBots::MessageInterpolator.call(text, config: @config, conversation: @conversation)
  end

  # ── Zoho CRM verification ──────────────────────────────────────────────────

  def zoho_check_enabled?
    @config.dig(:zoho_check, :enabled) == true
  end

  def zoho_hook
    @zoho_hook ||= Integrations::Hook.find_by(
      account: @conversation.account,
      app_id: 'zoho_crm',
      status: 'enabled'
    )
  end

  def fetch_zoho_record
    return nil unless zoho_hook

    contact = @conversation.contact
    ext = contact.additional_attributes&.dig('external')
    zoho_id     = ext&.dig('zoho_id')
    zoho_module = ext&.dig('zoho_module')

    if zoho_id.present?
      client = zoho_module == 'Contacts' ?
               Crm::Zoho::Api::ContactsClient.new(zoho_hook) :
               Crm::Zoho::Api::LeadsClient.new(zoho_hook)
      record = client.find(zoho_id)
      return record if record
    end

    leads_client    = Crm::Zoho::Api::LeadsClient.new(zoho_hook)
    contacts_client = Crm::Zoho::Api::ContactsClient.new(zoho_hook)

    leads = leads_client.search(phone: contact.phone_number, email: contact.email)
    return leads.first if leads.any?

    contact_records = contacts_client.search(phone: contact.phone_number, email: contact.email)
    contact_records.first
  rescue StandardError => e
    Rails.logger.error("[InternalFlow] Zoho fetch error for conv ##{@conversation.id}: #{e.message}")
    nil
  end

  def enrich_from_zoho(record)
    return unless record.is_a?(Hash)

    first  = record['First_Name'].to_s.strip
    last   = record['Last_Name'].to_s.strip
    nombre = [first, last].reject(&:blank?).join(' ')

    enriched = {}
    enriched['nombre']      = nombre                  if nombre.present?
    enriched['email_lead']  = record['Email'].to_s    if record['Email'].present?
    enriched['mobile_lead'] = record['Mobile'].to_s   if record['Mobile'].present?

    return if enriched.empty?

    @conversation.update!(custom_attributes: @conversation.custom_attributes.merge(enriched))
    Rails.logger.info("[InternalFlow] enriched from Zoho: #{enriched.keys.inspect}")
    sync_contact_name(enriched['nombre']) if enriched['nombre'].present?
  end
end
