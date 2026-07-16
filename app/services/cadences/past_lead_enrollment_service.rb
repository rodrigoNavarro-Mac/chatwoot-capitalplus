# Inscribe una conversacion que YA recibio una plantilla de WhatsApp fuera de la cadencia
# (manual desde el composer/API, o desde Crm::Zoho::SendInitialTemplateService) en la
# CadenceDefinition configurada para su inbox, arrancando en el paso que corresponde a esa
# plantilla en vez de repetir el paso 1. Pensado para el backfill de leads pasados via rake
# task (lib/tasks/cadences.rake), no se usa en el flujo en vivo (ese sigue siendo
# Cadences::EnrollmentService, disparado por CadenceListener#assignee_changed).
class Cadences::PastLeadEnrollmentService
  include Cadences::EventLogger

  Result = Struct.new(:conversation_id, :status, :detail, keyword_init: true)

  pattr_initialize [:conversation!]

  def call
    return result(:skipped, 'already_enrolled') if already_enrolled?
    return result(:skipped, 'not_eligible') unless eligible?

    last_message = last_template_message
    return result(:skipped, 'no_template_sent') if last_message.blank?

    match = matching_step(last_message)
    return result(:skipped, 'no_matching_step') if match.blank?

    enrollment = enroll_at_step!(match, last_message.created_at)
    result(:enrolled, "cadence_definition=#{match[:definition].id} step=#{match[:step]['position']} status=#{enrollment.status}")
  end

  private

  delegate :account, :inbox, :contact, to: :conversation

  def result(status, detail)
    Result.new(conversation_id: conversation.id, status: status, detail: detail)
  end

  def already_enrolled?
    CadenceEnrollment.exists?(conversation_id: conversation.id)
  end

  def eligible?
    Cadences::EligibilityChecker.new(conversation: conversation).eligible?
  end

  def last_template_message
    conversation.messages.outgoing
                .where("additional_attributes -> 'template_params' is not null")
                .order(created_at: :desc)
                .first
  end

  def matching_step(message)
    template_params = message.additional_attributes['template_params']
    name = template_params['name']
    language = template_params['language']
    return if name.blank?

    candidates = CadenceDefinition.active.for_inbox(inbox.id).filter_map do |definition|
      step = matching_step_definition(definition, name, language)
      { definition: definition, step: step.to_snapshot } if step
    end

    least_used(candidates)
  end

  def matching_step_definition(definition, name, language)
    definition.cadence_step_definitions.where(active: true).find do |step|
      step.template_name.casecmp?(name) && step.template_language.to_s.casecmp?(language.to_s)
    end
  end

  # Si varias CadenceDefinition (variantes A/B) comparten la misma plantilla en ese paso,
  # se reparte igual que un enrollment nuevo: la que hasta ahora tiene menos leads.
  def least_used(candidates)
    return candidates.first if candidates.size <= 1

    ids = candidates.map { |c| c[:definition].id }
    counts = CadenceEnrollment.where(cadence_definition_id: ids).group(:cadence_definition_id).count
    candidates.min_by { |c| counts[c[:definition].id] || 0 }
  end

  def enroll_at_step!(match, sent_at)
    definition = match[:definition]
    step = match[:step]
    snapshot = Cadences::StepsRepository.snapshot_for(definition)
    position = step['position']
    replied_at = first_reply_after(sent_at)

    enrollment = CadenceEnrollment.create!(enrollment_attributes(definition, snapshot, position, sent_at, replied_at))

    log_cadence_event(enrollment, 'cadence_started', step: 0, occurred_at: sent_at)
    log_cadence_event(enrollment, 'template_sent', step: position, template_key: step['template_key'], occurred_at: sent_at)
    after_create!(enrollment, position, replied_at)
    enrollment
  end

  def first_reply_after(time)
    conversation.messages.incoming.where('messages.created_at > ?', time).order(created_at: :asc).first&.created_at
  end

  def enrollment_attributes(definition, snapshot, position, sent_at, replied_at)
    recovered = replied_at.present? && position >= snapshot.size
    {
      account_id: account.id,
      conversation_id: conversation.id,
      contact_id: contact&.id,
      inbox_id: inbox.id,
      cadence_definition_id: definition.id,
      assignee_id: conversation.assignee_id,
      current_step: position,
      status: status_for(replied_at, recovered),
      last_template_sent_at: sent_at,
      last_lead_response_at: replied_at,
      next_action_at: replied_at.present? ? nil : sent_at + snapshot.find { |s| s['position'] == position }['wait_window_minutes'].minutes,
      steps_snapshot: snapshot
    }
  end

  def status_for(replied_at, recovered)
    return :waiting_response if replied_at.blank?

    recovered ? :recovered : :paused_by_response
  end

  def after_create!(enrollment, position, replied_at)
    if replied_at.blank?
      Cadences::CheckResponseJob.set(wait_until: enrollment.next_action_at).perform_later(enrollment.id, position)
      return
    end

    log_cadence_event(enrollment, 'lead_replied', step: position, occurred_at: replied_at)
    log_cadence_event(enrollment, enrollment.recovered? ? 'cadence_recovered' : 'cadence_paused', step: position, occurred_at: replied_at)
  end
end
