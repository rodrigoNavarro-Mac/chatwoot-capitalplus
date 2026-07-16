module Cadences::EventLogger
  # occurred_at es opcional: por defecto el modelo lo setea a Time.current (antes de esta
  # opción, todos los eventos quedaban con la hora en que corrio el codigo). Los backfills de
  # leads pasados (Cadences::PastLeadEnrollmentService) lo pasan explicito para que el
  # historial de analytics refleje cuando realmente ocurrio cada cosa, no cuando se corrio el
  # rake task.
  def log_cadence_event(enrollment, event_type, step: enrollment.current_step, occurred_at: nil, **attrs)
    CadenceEvent.create!(
      account_id: enrollment.account_id,
      cadence_enrollment_id: enrollment.id,
      conversation_id: enrollment.conversation_id,
      contact_id: enrollment.contact_id,
      event_type: event_type,
      step: step,
      occurred_at: occurred_at,
      template_key: attrs[:template_key],
      actor_type: attrs[:actor_type] || 'System',
      actor_id: attrs[:actor_id],
      metadata: attrs[:metadata] || {}
    )
  end
end
