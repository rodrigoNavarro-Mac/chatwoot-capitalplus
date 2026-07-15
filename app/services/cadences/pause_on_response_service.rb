class Cadences::PauseOnResponseService
  include Cadences::EventLogger

  pattr_initialize [:enrollment!, :message!]

  def perform
    enrollment.reload
    return unless CadenceEnrollment::ACTIVE_STATUSES.include?(enrollment.status)

    recovered = enrollment.current_step >= enrollment.total_steps
    enrollment.update!(
      status: recovered ? :recovered : :paused_by_response,
      last_lead_response_at: message.created_at,
      stopped_reason: nil
    )

    enrollment.cadence_call_tasks.pending.update_all(status: 'skipped') # rubocop:disable Rails/SkipsModelValidations

    log_cadence_event(enrollment, 'lead_replied')
    log_cadence_event(enrollment, recovered ? 'cadence_recovered' : 'cadence_paused')
  end
end
