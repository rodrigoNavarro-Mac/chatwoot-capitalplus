class Crm::Zoho::SendInitialTemplateService
  def initialize(account, params)
    @account            = account
    @phone              = params[:phone].to_s.gsub(/\D/, '')
    @contact_name       = params[:contact_name].to_s.strip
    @desarrollo         = params[:desarrollo].to_s.strip
    @template_name      = params[:template_name].to_s.strip
    @template_language  = params[:template_language].to_s.strip
    @body_params        = Array(params[:body_params])
    @header_image_url   = params[:header_image_url].to_s.strip.presence
    @assignee_email     = params[:assignee_email].to_s.strip.downcase.presence
  end

  def perform
    raise 'phone_required' if @phone.blank?
    raise 'desarrollo_required' if @desarrollo.blank?
    raise 'template_name_required' if @template_name.blank?

    inbox = find_inbox!

    contact_inbox = ContactInboxWithContactBuilder.new(
      inbox: inbox,
      contact_attributes: {
        name:         @contact_name.presence || @phone,
        phone_number: "+#{@phone}"
      },
      source_id: @phone
    ).perform

    channel = inbox.channel
    name, namespace, lang_code, parameters, rendered_body, stored_template_params = build_template_info(channel)
    raise 'template_not_found_or_not_approved' if parameters.nil?

    wamid = channel.send_template("+#{@phone}", { name: name, namespace: namespace, lang_code: lang_code, parameters: parameters }, nil)
    raise 'template_send_failed' unless wamid

    conversation = find_or_create_conversation(contact_inbox, inbox)
    assign_agent(conversation)
    conversation.messages.create!(
      message_type:          :outgoing,
      account_id:            @account.id,
      inbox_id:              inbox.id,
      content:               rendered_body.presence || @template_name,
      source_id:             wamid,
      status:                :sent,
      additional_attributes: { template_params: stored_template_params }
    )

    Rails.logger.info("[ZohoCRM][SendTemplate] Sent '#{@template_name}' to +#{@phone} via inbox ##{inbox.id}")
  end

  private

  def assign_agent(conversation)
    return if @assignee_email.blank?

    agent = @account.agents.find_by('lower(email) = ?', @assignee_email)
    return Rails.logger.warn("[ZohoCRM][SendTemplate] Agent not found for email: #{@assignee_email}") unless agent

    conversation.update!(assignee: agent)
    Rails.logger.info("[ZohoCRM][SendTemplate] Assigned conversation ##{conversation.id} to #{agent.name}")
  end

  def find_or_create_conversation(contact_inbox, inbox)
    existing = Conversation.where(
      inbox_id:         inbox.id,
      contact_id:       contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id
    ).where(status: [Conversation.statuses[:open], Conversation.statuses[:pending]])
                            .order(created_at: :desc)
                            .first

    if existing
      existing.update!(status: :open) if existing.pending?
      return existing
    end

    Conversation.create!(
      account_id:       @account.id,
      inbox_id:         inbox.id,
      contact_id:       contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id,
      status:           :open
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

  def build_template_info(channel)
    template = channel.message_templates.find do |t|
      t['name']&.downcase == @template_name.downcase &&
        t['language']&.downcase == @template_language.downcase &&
        t['status']&.downcase == 'approved'
    end

    body_map = if template&.dig('parameter_format') == 'NAMED'
                 named_keys = extract_named_param_names(template)
                 named_keys.each_with_index.each_with_object({}) { |(name, i), h| h[name] = @body_params[i].to_s }
               else
                 @body_params.each_with_index.each_with_object({}) { |(val, i), h| h[(i + 1).to_s] = val }
               end

    processed_params = { 'body' => body_map }
    processed_params['header'] = { 'media_url' => @header_image_url, 'media_type' => 'image' } if @header_image_url

    template_params = {
      'name'             => @template_name,
      'language'         => @template_language,
      'processed_params' => processed_params
    }

    api_params = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: template_params
    ).call

    # api_params = [name, namespace, lang_code, parameters]; guardamos el namespace real
    # (resuelto por TemplateProcessorService) en el marcador que persistimos en el mensaje,
    # para poder detectar despues "que plantilla se le mando a este lead" sin heuristicas de
    # texto. Se omite si viene vacio (Cloud API no lo usa) porque el schema del mensaje exige
    # que, si namespace esta presente, sea un string.
    template_params['namespace'] = api_params[1] if api_params[1].present?

    rendered_body = render_template_body(template, body_map)
    api_params + [rendered_body, template_params]
  end

  def render_template_body(template, body_map)
    return nil unless template

    body_component = template['components']&.find { |c| c['type']&.upcase == 'BODY' }
    return nil unless body_component

    text = body_component['text'].to_s
    body_map.each { |key, value| text = text.gsub("{{#{key}}}", value.to_s) }
    text.gsub(/\{\{[^}]+\}\}/, '').strip
  end

  def extract_named_param_names(template)
    body_component = template['components']&.find { |c| c['type']&.upcase == 'BODY' }
    return [] unless body_component

    named_params = body_component.dig('example', 'body_text_named_params')
    return named_params.map { |p| p['param_name'] } if named_params.present?

    (body_component['text'] || '').scan(/\{\{(\w+)\}\}/).flatten
  end
end
