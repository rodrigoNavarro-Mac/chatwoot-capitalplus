class Cadences::Analytics::StepsBuilder < Cadences::Analytics::BaseBuilder
  def build
    attach_drop_off(observed_steps.map { |step, template_key| step_metrics(step, template_key) })
  end

  private

  # El drop-off se calcula contra el total del step anterior (sumando todos sus template_key),
  # no contra la fila anterior de la lista: un step puede tener varias filas (una por
  # template_key distinto usado historicamente en esa posicion) y comparar filas consecutivas
  # calcularia el drop-off entre dos template_key del MISMO step en vez del step anterior real.
  def attach_drop_off(metrics)
    step_totals = metrics.each_with_object(Hash.new(0)) { |metric, totals| totals[metric[:step]] += metric[:sent] }
    ordered_steps = step_totals.keys.sort

    metrics.each do |metric|
      step_index = ordered_steps.index(metric[:step])
      previous_sent = step_index.zero? ? step_totals[metric[:step]] : step_totals[ordered_steps[step_index - 1]]
      metric[:drop_off_rate] = safe_rate(previous_sent - step_totals[metric[:step]], previous_sent)
    end
    metrics
  end

  # Los pasos ya no son una lista fija: se derivan de lo realmente enviado (CadenceEvent),
  # así el reporte sigue siendo correcto aunque la config de pasos haya cambiado desde
  # entonces, y funciona igual con inboxes que tienen cadencias de distinto largo.
  def observed_steps
    event_scope.where(event_type: 'template_sent').distinct.pluck(:step, :template_key).compact.sort_by(&:first)
  end

  def step_metrics(step, template_key)
    sent = event_scope.where(event_type: 'template_sent', step: step, template_key: template_key).count
    responded = responded_count(step)

    {
      step: step,
      template_key: template_key,
      sent: sent,
      responded: responded,
      response_rate: safe_rate(responded, sent),
      no_response: sent - responded,
      avg_response_time_seconds: avg_response_time(step),
      advanced_to_next_step: enrollment_scope.where('current_step > ?', step).count
    }.merge(call_task_metrics(step))
  end

  def responded_count(step)
    enrollment_scope.where(current_step: step, status: RESPONDED_STATUSES).count
  end

  def call_task_metrics(step)
    call_tasks = call_task_scope.where(step: step)
    required = call_tasks.count
    completed = call_tasks.completed.count

    { call_tasks_required: required, call_tasks_completed: completed, call_compliance_rate: safe_rate(completed, required) }
  end

  def avg_response_time(step)
    pairs = enrollment_scope.where(current_step: step, status: RESPONDED_STATUSES).pluck(:last_template_sent_at, :last_lead_response_at)
    average_seconds(pairs)
  end
end
