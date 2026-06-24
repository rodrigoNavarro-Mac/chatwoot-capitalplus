class AgentBots::InternalFlowHandlerService
  def initialize(agent_bot, conversation, message_content)
    @agent_bot = agent_bot
    @conversation = conversation
    @message_content_raw = message_content.to_s.strip
    @message_content = @message_content_raw.downcase
    @config = agent_bot.bot_config.with_indifferent_access
    @variables = @config[:variables] || {}
  end

  def perform
    unless processable?
      Rails.logger.info("[InternalFlow] Conv ##{@conversation.id} — no processable")
      return
    end

    current_step_name = @conversation.custom_attributes['_bot_current_step']
    Rails.logger.info("[InternalFlow] Conv ##{@conversation.id} step=#{current_step_name.inspect} msg=#{@message_content.truncate(40).inspect}")

    if current_step_name.blank?
      send_initial_step
      return
    end

    navigate_from(current_step_name)
  end

  private

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
    return false if @conversation.open?

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
    result = @variables.reduce(text) { |msg, (key, value)| msg.gsub("{{#{key}}}", value.to_s) }
    @conversation.custom_attributes.each do |key, value|
      next if key.to_s.start_with?('_')

      result = result.gsub("{{#{key}}}", value.to_s)
    end
    result.gsub(/\{\{[^}]+\}\}/, '')
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

  # Returns the Zoho record hash if found, nil if not found.
  # On API error returns nil (fail-open: treat as not found).
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

  # Stores useful Zoho lead fields in custom_attributes so templates can use {{nombre}}, {{email_lead}}, etc.
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
