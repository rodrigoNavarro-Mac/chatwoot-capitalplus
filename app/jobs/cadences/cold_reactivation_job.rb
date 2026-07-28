# Agregar un paso nuevo a una CadenceDefinition es silencioso: nunca toca enrollments ya
# inscritos (steps_snapshot queda congelado desde el enroll!, ver Cadences::StepsRepository).
# Esto significa que un enrollment "cold" (agotó todos los pasos que existían en su momento
# sin que el lead respondiera) se queda cold para siempre aunque luego se agregue un paso
# nuevo a la cadencia. Este job periódico detecta esos casos y los reactiva.
class Cadences::ColdReactivationJob < ApplicationJob
  include Cadences::EventLogger

  queue_as :scheduled_jobs

  def perform
    CadenceEnrollment.cold.find_each do |enrollment|
      reactivate_if_cadence_grew!(enrollment)
    rescue StandardError => e
      Rails.logger.error "[Cadences::ColdReactivationJob] enrollment=#{enrollment.id} error=#{e.message}"
    end
  end

  private

  def reactivate_if_cadence_grew!(enrollment)
    live_step_count = enrollment.cadence_definition.cadence_step_definitions.where(active: true).count
    return if live_step_count <= enrollment.total_steps

    snapshot = Cadences::StepsRepository.snapshot_for(enrollment.cadence_definition)
    return if snapshot.blank?

    enrollment.update!(status: :active, stopped_reason: nil, steps_snapshot: snapshot, next_action_at: Time.current)
    log_cadence_event(enrollment, 'cadence_resumed', metadata: { reason: 'new_step_added' })
    Cadences::AdvanceJob.set(wait_until: Time.current).perform_later(enrollment.id)
  end
end
