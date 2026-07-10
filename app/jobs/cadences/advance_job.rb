class Cadences::AdvanceJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(enrollment_id)
    enrollment = CadenceEnrollment.find_by(id: enrollment_id)
    return unless enrollment

    Cadences::StepExecutor.new(enrollment: enrollment).execute_current_step!
  end
end
