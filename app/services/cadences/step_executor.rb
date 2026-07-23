class Cadences::StepExecutor
  include Cadences::EventLogger

  PseudoCampaign = Struct.new(:sender, :inbox, :account)
  RATE_LIMIT_RETRY_JITTER = (2.0..5.0)

  pattr_initialize [:enrollment!]

  def execute_current_step!
    enrollment.reload
    return unless %w[active pending_agent_call].include?(enrollment.status)
    return if enrollment.responded_since_last_template?
    return terminate!('ineligible') unless still_eligible?

    step_number = enrollment.current_step + 1
    return if enrollment.current_step >= step_number

    definition = enrollment.step_definition_for(step_number)
    return terminate!('no_next_step') if definition.blank?

    return reschedule_for_rate_limit! unless rate_limiter.claim_slot!

    send_step(definition)
  end

  private

  delegate :conversation, to: :enrollment
  delegate :inbox, :account, :contact, to: :conversation

  def still_eligible?
    Cadences::EligibilityChecker.new(conversation: conversation).eligible?
  end

  def rate_limiter
    @rate_limiter ||= Cadences::SendRateLimiter.new(inbox: inbox)
  end

  # A diferencia de terminate!, esto no marca el enrollment como failed: el status/current_step
  # quedan igual y AdvanceJob se vuelve a encolar un poco despues (con jitter para que varios
  # enrollments compitiendo por el mismo turno no reintenten todos en el mismo instante).
  def reschedule_for_rate_limit!
    Cadences::AdvanceJob.set(wait_until: Time.current + rand(RATE_LIMIT_RETRY_JITTER).seconds).perform_later(enrollment.id)
  end

  def send_step(definition)
    template_params = resolve_template_params(definition)
    return terminate!('template_resolution_failed') if template_params.blank?

    wa_message_id, error_detail = send_whatsapp_template(template_params)
    return terminate!('send_failed', error_detail) if wa_message_id.blank?

    persist_message(definition, template_params, wa_message_id)

    step_number = definition[:position]
    enrollment.update!(
      current_step: step_number,
      status: :waiting_response,
      last_template_sent_at: Time.current,
      next_action_at: Time.current + definition[:wait_window_minutes].minutes
    )
    log_cadence_event(enrollment, 'template_sent', step: step_number, template_key: definition[:template_key],
                                                   metadata: { wa_message_id: wa_message_id })

    Cadences::CheckResponseJob.set(wait_until: enrollment.next_action_at).perform_later(enrollment.id, step_number)
  end

  def resolve_template_params(definition)
    template_params = {
      'name' => definition[:template_name],
      'language' => definition[:template_language],
      'namespace' => definition[:template_namespace],
      'processed_params' => processed_params_for(definition)
    }

    Whatsapp::LiquidTemplateProcessorService.new(campaign: pseudo_campaign, contact: contact).process_template_params(template_params)
  end

  # Liquid resuelve cada valor (ej. "{{ contact.name }}") al momento de enviar, tanto en
  # el header (media_url) como en las variables del cuerpo — mismo mecanismo, solo hay que
  # darle la forma que Whatsapp::TemplateProcessorService espera para cada componente.
  def processed_params_for(definition)
    { 'header' => header_params(definition), 'body' => body_params(definition) }.compact
  end

  def header_params(definition)
    return nil if definition[:media_url].blank?

    {
      'media_url' => definition[:media_url],
      'media_type' => definition[:media_type],
      'media_name' => definition[:media_name]
    }.compact
  end

  def body_params(definition)
    variables = definition[:body_variables]
    return nil if variables.blank?

    variables
  end

  def pseudo_campaign
    PseudoCampaign.new(conversation.assignee, inbox, account)
  end

  def send_whatsapp_template(template_params)
    channel = inbox.channel
    processor = Whatsapp::TemplateProcessorService.new(channel: channel, template_params: template_params)
    name, namespace, lang_code, processed_parameters = processor.call
    return [nil, 'template_processor_returned_blank_name'] if name.blank?

    template_info = { name: name, namespace: namespace, lang_code: lang_code, parameters: processed_parameters }
    provider = channel.provider_service
    wa_message_id = provider.send_template(contact.phone_number, template_info, nil)
    [wa_message_id, provider.last_send_error]
  rescue StandardError => e
    Rails.logger.error "[Cadences::StepExecutor] send failed enrollment=#{enrollment.id}: #{e.message}"
    [nil, e.message]
  end

  # A diferencia del composer/Zoho (donde el Message ya existe antes de pegarle al provider),
  # aquí el envío es el primer paso: sin esto, el HTTP a Meta triunfa pero nada queda en
  # conversation.messages, así que el agente nunca ve la plantilla en el chat.
  def persist_message(definition, template_params, wa_message_id)
    message = conversation.messages.create!(
      message_type: :outgoing,
      account_id: account.id,
      inbox_id: inbox.id,
      content: definition[:template_name],
      source_id: wa_message_id,
      status: :sent,
      additional_attributes: { template_params: template_params.compact }
    )
    attach_header_media(message, definition)
  end

  def attach_header_media(message, definition)
    Whatsapp::TemplateHeaderAttachmentService.new(message: message, media_url: definition[:media_url], media_type: definition[:media_type]).call
  end

  def terminate!(reason, detail = nil)
    stopped_reason = detail.present? ? "#{reason}: #{detail}".truncate(500) : reason
    enrollment.update!(status: :failed, stopped_reason: stopped_reason)
    log_cadence_event(enrollment, 'cadence_failed', metadata: { reason: reason, detail: detail }.compact)
  end
end
