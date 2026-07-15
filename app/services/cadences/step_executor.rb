class Cadences::StepExecutor
  include Cadences::EventLogger

  PseudoCampaign = Struct.new(:sender, :inbox, :account)

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

    send_step(definition)
  end

  private

  delegate :conversation, to: :enrollment
  delegate :inbox, :account, :contact, to: :conversation

  def still_eligible?
    Cadences::EligibilityChecker.new(conversation: conversation).eligible?
  end

  def send_step(definition)
    template_params = resolve_template_params(definition)
    return terminate!('template_resolution_failed') if template_params.blank?

    wa_message_id = send_whatsapp_template(template_params)
    return terminate!('send_failed') if wa_message_id.blank?

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
      'processed_params' => header_params(definition)
    }

    Whatsapp::LiquidTemplateProcessorService.new(campaign: pseudo_campaign, contact: contact).process_template_params(template_params)
  end

  def header_params(definition)
    return {} if definition[:media_url].blank?

    {
      'header' => {
        'media_url' => definition[:media_url],
        'media_type' => definition[:media_type],
        'media_name' => definition[:media_name]
      }.compact
    }
  end

  def pseudo_campaign
    PseudoCampaign.new(conversation.assignee, inbox, account)
  end

  def send_whatsapp_template(template_params)
    channel = inbox.channel
    processor = Whatsapp::TemplateProcessorService.new(channel: channel, template_params: template_params)
    name, namespace, lang_code, processed_parameters = processor.call
    return if name.blank?

    template_info = { name: name, namespace: namespace, lang_code: lang_code, parameters: processed_parameters }
    channel.provider_service.send_template(contact.phone_number, template_info, nil)
  rescue StandardError => e
    Rails.logger.error "[Cadences::StepExecutor] send failed enrollment=#{enrollment.id}: #{e.message}"
    nil
  end

  def terminate!(reason)
    enrollment.update!(status: :failed, stopped_reason: reason)
    log_cadence_event(enrollment, 'cadence_failed', metadata: { reason: reason })
  end
end
