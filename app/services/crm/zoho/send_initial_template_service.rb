class Crm::Zoho::SendInitialTemplateService
  def initialize(account, params)
    @account    = account
    @request_id = SecureRandom.uuid
    assign_scalar_fields(params)
    assign_template_fields(params)
  end

  def perform
    validate_required_fields!

    inbox = find_inbox!
    contact_inbox = build_contact_inbox(inbox)

    channel = inbox.channel
    template = find_template(channel)
    raise 'template_not_found_or_not_approved' unless template

    named_keys = named_parameter_keys(template)
    components = build_components(named_keys)

    log_payload(components)
    sender = Crm::Zoho::TemplateSender.new(channel: channel, request_id: @request_id)
    wamid = sender.call("+#{@phone}", @template_name, @template_language, components)

    persist_message(inbox, contact_inbox, template, named_keys, wamid)

    Rails.logger.info("[ZohoCRM][SendTemplate][#{@request_id}] Sent '#{@template_name}' to +#{@phone} via inbox ##{inbox.id}")
  end

  private

  def assign_scalar_fields(params)
    @phone             = params[:phone].to_s.gsub(/\D/, '')
    @contact_name      = params[:contact_name].to_s.strip
    @desarrollo        = params[:desarrollo].to_s.strip
    @template_name     = params[:template_name].to_s.strip
    @template_language = params[:template_language].to_s.strip
    @assignee_email    = params[:assignee_email].to_s.strip.downcase.presence
  end

  def assign_template_fields(params)
    normalized = Crm::Zoho::TemplateParamsNormalizer.new(params).normalize
    @header        = normalized[:header]
    @body_params   = normalized[:body_params]
    @button_params = normalized[:button_params]
  end

  def build_contact_inbox(inbox)
    ContactInboxWithContactBuilder.new(
      inbox: inbox,
      contact_attributes: {
        name: @contact_name.presence || @phone,
        phone_number: "+#{@phone}"
      },
      source_id: @phone
    ).perform
  end

  def build_components(named_keys)
    Whatsapp::TemplatePayloadBuilder.new(
      header: @header,
      body_params: @body_params,
      button_params: @button_params,
      named_parameter_keys: named_keys
    ).call
  end

  def persist_message(inbox, contact_inbox, template, named_keys, wamid)
    conversation = find_or_create_conversation(contact_inbox, inbox)
    assign_agent(conversation)
    conversation.messages.create!(
      message_type: :outgoing,
      account_id: @account.id,
      inbox_id: inbox.id,
      content: render_template_body(template, named_keys).presence || @template_name,
      source_id: wamid,
      status: :sent,
      additional_attributes: {
        template_params: {
          'name' => @template_name,
          'language' => @template_language,
          'header' => @header,
          'body_params' => @body_params,
          'button_params' => @button_params
        }
      }
    )
  end

  def validate_required_fields!
    raise 'phone_required' if @phone.blank?
    raise 'phone_invalid' unless @phone.length.between?(8, 15)
    raise 'desarrollo_required' if @desarrollo.blank?
    raise 'template_name_required' if @template_name.blank?
    raise 'template_language_required' if @template_language.blank?
  end

  def assign_agent(conversation)
    return if @assignee_email.blank?

    agent = @account.agents.find_by('lower(email) = ?', @assignee_email)
    return Rails.logger.warn("[ZohoCRM][SendTemplate][#{@request_id}] Agent not found for email: #{@assignee_email}") unless agent

    conversation.update!(assignee: agent)
    Rails.logger.info("[ZohoCRM][SendTemplate][#{@request_id}] Assigned conversation ##{conversation.id} to #{agent.name}")
  end

  def find_or_create_conversation(contact_inbox, inbox)
    existing = Conversation.where(
      inbox_id: inbox.id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id
    ).where(status: [Conversation.statuses[:open], Conversation.statuses[:pending]])
                           .order(created_at: :desc)
                           .first

    if existing
      existing.update!(status: :open) if existing.pending?
      return existing
    end

    Conversation.create!(
      account_id: @account.id,
      inbox_id: inbox.id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id,
      status: :open
    )
  end

  def find_inbox!
    inbox = @account.inboxes
                    .where(channel_type: 'Channel::Whatsapp')
                    .joins(agent_bot_inbox: :agent_bot)
                    .find { |i| i.agent_bot&.bot_config&.dig('variables', 'desarrollo') == @desarrollo }
    raise 'inbox_not_found' unless inbox

    inbox
  end

  def find_template(channel)
    channel.message_templates.find do |t|
      t['name']&.downcase == @template_name.downcase &&
        t['language']&.downcase == @template_language.downcase &&
        t['status']&.downcase == 'approved'
    end
  end

  # Only the legacy positional body_params (plain strings) need this: a NAMED-format template
  # expects each body parameter tagged with a `parameter_name` instead of relying on position.
  # Typed body_params already carry their own shape and don't go through this path.
  def named_parameter_keys(template)
    return nil unless template['parameter_format'] == 'NAMED'
    return nil unless @body_params.present? && @body_params.all?(String)

    extract_named_param_names(template)
  end

  def extract_named_param_names(template)
    body_component = template['components']&.find { |c| c['type']&.upcase == 'BODY' }
    return [] unless body_component

    named_params = body_component.dig('example', 'body_text_named_params')
    return named_params.pluck('param_name') if named_params.present?

    (body_component['text'] || '').scan(/\{\{(\w+)\}\}/).flatten
  end

  def log_payload(components)
    sanitized_payload = { name: @template_name, language: @template_language, components: components }
    Rails.logger.info("[ZohoCRM][SendTemplate][#{@request_id}] WhatsApp template payload: #{sanitized_payload.to_json}")
  end

  def render_template_body(template, named_keys)
    body_component = template['components']&.find { |c| c['type']&.upcase == 'BODY' }
    return nil unless body_component

    text = body_component['text'].to_s
    body_placeholder_values(named_keys).each { |placeholder, value| text = text.gsub("{{#{placeholder}}}", value) }
    text.gsub(/\{\{[^}]+\}\}/, '').strip
  end

  def body_placeholder_values(named_keys)
    @body_params.each_with_index.filter_map do |param, i|
      placeholder = named_keys ? named_keys[i] : (i + 1).to_s
      next unless placeholder

      [placeholder, body_param_display_value(param)]
    end
  end

  def body_param_display_value(param)
    return param.to_s unless param.is_a?(Hash)

    param = param.stringify_keys
    case param['type']
    when 'text' then param['text'].to_s
    when 'currency' then param.dig('currency', 'fallback_value').to_s
    when 'date_time' then param.dig('date_time', 'fallback_value').to_s
    else ''
    end
  end
end
