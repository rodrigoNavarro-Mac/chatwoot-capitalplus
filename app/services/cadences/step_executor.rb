class Cadences::StepExecutor
  include Cadences::EventLogger

  PseudoCampaign = Struct.new(:sender, :inbox, :account)
  RATE_LIMIT_RETRY_JITTER = (2.0..5.0)
  # Excepciones de red que valen la pena reintentar (a diferencia de bugs de código,
  # que StandardError también atraparía pero no tiene sentido reintentar 5 veces).
  NETWORK_ERROR_CLASSES = [Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED, SocketError].freeze
  # Links de "compartir" de servicios como Google Drive no devuelven el archivo directamente:
  # devuelven una pagina HTML de vista previa. Meta nunca puede descargarlos como media, sin
  # importar cuantas veces se reintente -- a diferencia de, por ejemplo, una URL sin extension
  # de un object storage (Vercel Blob, S3, etc.), que si suele servir el Content-Type correcto
  # y funciona bien. Ver incidente 2026-07-29/30: video con link de Google Drive reintentando
  # en loop indefinidamente (665 envios en 7 dias antes de detectarse).
  KNOWN_INVALID_MEDIA_HOST_PATTERNS = [
    %r{drive\.google\.com/.*/view}i,
    %r{drive\.google\.com/open\?}i
  ].freeze

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
    return handle_send_failure("invalid_media_url: #{definition[:media_url]}", nil, false) if invalid_media_url?(definition)

    template_params = resolve_template_params(definition)
    return terminate!('template_resolution_failed') if template_params.blank?

    wa_message_id, error_detail, error_code, transient = send_whatsapp_template(template_params)
    return handle_send_failure(error_detail, error_code, transient) if wa_message_id.blank?

    persist_message(definition, template_params, wa_message_id)
    advance_after_successful_send!(definition, wa_message_id)
  end

  def handle_send_failure(error_detail, error_code, transient)
    Cadences::SendFailureHandler.new(
      enrollment: enrollment, error_detail: error_detail, error_code: error_code, transient: transient
    ).call
  end

  def advance_after_successful_send!(definition, wa_message_id)
    step_number = definition[:position]
    attrs = {
      current_step: step_number,
      status: :waiting_response,
      last_template_sent_at: Time.current,
      next_action_at: Time.current + definition[:wait_window_minutes].minutes
    }
    # Un step con media puede ser aceptado por Meta en el momento y fallar la validacion de la
    # media de forma asincrona minutos despues (ver Cadences::SendFailureHandler); resetear el
    # contador de reintentos aqui, antes de esa confirmacion, hace que el conteo real se pierda
    # y el ciclo de reintento nunca escale ni termine (incidente 2026-07-29: 81 envios cada
    # ~2min sin parar, siempre en "intento 1"). Para pasos sin media, "aceptado" por Meta si es
    # la confirmacion final, asi que ahi el reset es correcto.
    attrs[:send_retry_count] = 0 if definition[:media_url].blank?
    enrollment.update!(attrs)
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

  def invalid_media_url?(definition)
    media_url = definition[:media_url]
    return false if media_url.blank?

    KNOWN_INVALID_MEDIA_HOST_PATTERNS.any? { |pattern| media_url.match?(pattern) }
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

  def channel
    @channel ||= inbox.channel
  end

  def send_whatsapp_template(template_params)
    processor = Whatsapp::TemplateProcessorService.new(channel: channel, template_params: template_params)
    name, namespace, lang_code, processed_parameters = processor.call
    return [nil, 'template_processor_returned_blank_name', nil, false] if name.blank?

    template_info = { name: name, namespace: namespace, lang_code: lang_code, parameters: processed_parameters }
    provider = channel.provider_service
    wa_message_id = provider.send_template(contact.phone_number, template_info, nil)
    [wa_message_id, provider.last_send_error, provider.last_api_error&.dig('code'), nil]
  rescue *NETWORK_ERROR_CLASSES => e
    log_send_error(e, transient: true)
  rescue StandardError => e
    log_send_error(e, transient: false)
  end

  def log_send_error(error, transient:)
    Rails.logger.error "[Cadences::StepExecutor] send failed enrollment=#{enrollment.id}: #{error.message}"
    [nil, error.message, nil, transient]
  end

  # A diferencia del composer/Zoho (donde el Message ya existe antes de pegarle al provider),
  # aquí el envío es el primer paso: sin esto, el HTTP a Meta triunfa pero nada queda en
  # conversation.messages, así que el agente nunca ve la plantilla en el chat.
  def persist_message(definition, template_params, wa_message_id)
    message = conversation.messages.create!(
      message_type: :outgoing,
      account_id: account.id,
      inbox_id: inbox.id,
      content: rendered_body(template_params) || definition[:template_name],
      source_id: wa_message_id,
      status: :sent,
      additional_attributes: {
        template_params: template_params.compact,
        # Enlaza el mensaje a su enrollment/paso para que, si Meta reporta el fallo por
        # webhook de status más tarde (ej. el video no pasó su validación de descarga),
        # Whatsapp::IncomingMessageBaseService pueda encontrar el enrollment correcto y
        # aplicar la misma política de reintento (ver Cadences::SendFailureHandler).
        cadence_enrollment_id: enrollment.id,
        cadence_step: definition[:position]
      }
    )
    attach_header_media(message, definition)
  end

  # El chat debe mostrar el texto real que recibio el lead, no el nombre interno de la
  # plantilla (ej. "wa_segundo_intento") — mismo criterio que
  # Crm::Zoho::SendInitialTemplateService#render_template_body.
  def rendered_body(template_params)
    body_component = body_component_for(template_params)
    return nil if body_component.blank?

    substitute_placeholders(body_component['text'].to_s, template_params)
  end

  def body_component_for(template_params)
    registered_template = find_registered_template(template_params)
    return nil if registered_template.blank?

    registered_template['components']&.find { |c| c['type']&.upcase == 'BODY' }
  end

  def substitute_placeholders(text, template_params)
    (template_params.dig('processed_params', 'body') || {}).each do |placeholder, value|
      text = text.gsub("{{#{placeholder}}}", value.to_s)
    end
    text.gsub(/\{\{[^}]+\}\}/, '').strip.presence
  end

  def find_registered_template(template_params)
    channel.message_templates.find do |t|
      t['name'] == template_params['name'] && t['language']&.downcase == template_params['language'].to_s.downcase
    end
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
