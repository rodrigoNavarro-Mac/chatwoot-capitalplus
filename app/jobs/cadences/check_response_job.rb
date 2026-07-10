class Cadences::CheckResponseJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(enrollment_id, step)
    enrollment = CadenceEnrollment.find_by(id: enrollment_id)
    return unless enrollment

    Cadences::ResponseCheckService.new(enrollment: enrollment, step: step).perform
  end
end
