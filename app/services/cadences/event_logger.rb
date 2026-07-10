module Cadences::EventLogger
  def log_cadence_event(enrollment, event_type, step: enrollment.current_step, **attrs)
    CadenceEvent.create!(
      account_id: enrollment.account_id,
      cadence_enrollment_id: enrollment.id,
      conversation_id: enrollment.conversation_id,
      contact_id: enrollment.contact_id,
      event_type: event_type,
      step: step,
      template_key: attrs[:template_key],
      actor_type: attrs[:actor_type] || 'System',
      actor_id: attrs[:actor_id],
      metadata: attrs[:metadata] || {}
    )
  end
end
