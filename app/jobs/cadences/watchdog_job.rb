# Red de seguridad: reintenta enrollments cuyo next_action_at ya venció pero cuyo
# AdvanceJob/CheckResponseJob no corrió (perdido por un deploy, restart de Sidekiq, etc.).
# Idempotente: los guards en StepExecutor/ResponseCheckService evitan reenvíos o
# tareas de llamada duplicadas si el job original sí llegó a ejecutarse.
class Cadences::WatchdogJob < ApplicationJob
  queue_as :scheduled_jobs

  STALE_THRESHOLD = 10.minutes

  def perform
    overdue_enrollments.find_each do |enrollment|
      retrigger(enrollment)
    rescue StandardError => e
      Rails.logger.error "[Cadences::WatchdogJob] enrollment=#{enrollment.id} error=#{e.message}"
    end
  end

  private

  def overdue_enrollments
    CadenceEnrollment.where(status: CadenceEnrollment::ACTIVE_STATUSES)
                     .where.not(next_action_at: nil)
                     .where('next_action_at < ?', STALE_THRESHOLD.ago)
  end

  def retrigger(enrollment)
    if enrollment.waiting_response?
      Cadences::CheckResponseJob.perform_later(enrollment.id, enrollment.current_step)
    else
      Cadences::AdvanceJob.perform_later(enrollment.id)
    end
  end
end
