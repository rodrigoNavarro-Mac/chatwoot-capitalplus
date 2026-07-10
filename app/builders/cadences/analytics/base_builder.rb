class Cadences::Analytics::BaseBuilder
  RESPONDED_STATUSES = %w[paused_by_response recovered].freeze

  pattr_initialize [:account!, { filters: {} }]

  private

  def enrollment_scope
    @enrollment_scope ||= account.cadence_enrollments
                                 .filter_by_date_range(filters[:range])
                                 .filter_by_inbox_id(filters[:inbox_id])
                                 .filter_by_assignee_id(filters[:assignee_id])
                                 .filter_by_team_id(filters[:team_id])
                                 .filter_by_status(filters[:status])
                                 .filter_by_step(filters[:step])
  end

  def enrollment_ids
    @enrollment_ids ||= enrollment_scope.pluck(:id)
  end

  def call_task_scope
    CadenceCallTask.where(cadence_enrollment_id: enrollment_ids)
  end

  def event_scope
    CadenceEvent.where(cadence_enrollment_id: enrollment_ids)
  end

  def safe_rate(numerator, denominator)
    return 0.0 if denominator.to_i.zero?

    (numerator.to_f / denominator * 100).round(2)
  end

  def average_seconds(pairs)
    diffs = pairs.filter_map { |start, finish| finish - start if start.present? && finish.present? }
    return 0.0 if diffs.empty?

    (diffs.sum / diffs.size).round(2)
  end
end
