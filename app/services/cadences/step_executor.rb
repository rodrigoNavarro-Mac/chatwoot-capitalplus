class Cadences::StepExecutor
  include Cadences::EventLogger

  pattr_initialize [:enrollment!]

  def execute_current_step!
    enrollment.reload
    return unless %w[active pending_agent_call].include?(enrollment.status)
    return if enrollment.responded_since_last_template?
    return terminate!('ineligible') unless still_eligible?

    step_number = enrollment.current_step + 1
    return if enrollment.current_step >= step_number

    definition = Cadences::StepDefinitions.for_step(step_number)
    send_step(definition)
  end

  private

  delegate :conversation, to: :enrollment

  def still_eligible?
    Cadences::EligibilityChecker.new(conversation: conversation).eligible?
  end

  def send_step(definition)
    template_params = Cadences::TemplateResolver.new(template_key: definition[:template_key], conversation: conversation).resolve
    return terminate!('template_resolution_failed') if template_params.blank?

    wa_message_id = send_whatsapp_template(template_params)
    return terminate!('send_failed') if wa_message_id.blank?

    step_number = definition[:step]
    enrollment.update!(
      current_step: step_number,
      status: :waiting_response,
      last_template_sent_at: Time.current,
      next_action_at: Time.current + definition[:wait_window]
    )
    log_cadence_event(enrollment, 'template_sent', step: step_number, template_key: definition[:template_key],
                                                   metadata: { wa_message_id: wa_message_id })

    Cadences::CheckResponseJob.set(wait_until: enrollment.next_action_at).perform_later(enrollment.id, step_number)
  end

  def send_whatsapp_template(template_params)
    channel = conversation.inbox.channel
    processor = Whatsapp::TemplateProcessorService.new(channel: channel, template_params: template_params)
    name, namespace, lang_code, processed_parameters = processor.call
    return if name.blank?

    template_info = { name: name, namespace: namespace, lang_code: lang_code, parameters: processed_parameters }
    channel.provider_service.send_template(conversation.contact.phone_number, template_info, nil)
  rescue StandardError => e
    Rails.logger.error "[Cadences::StepExecutor] send failed enrollment=#{enrollment.id}: #{e.message}"
    nil
  end

  def terminate!(reason)
    enrollment.update!(status: :failed, stopped_reason: reason)
    log_cadence_event(enrollment, 'cadence_failed', metadata: { reason: reason })
  end
end
