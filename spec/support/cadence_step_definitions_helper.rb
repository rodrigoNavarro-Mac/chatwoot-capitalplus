module CadenceStepDefinitionsHelper
  # Da de alta una CadenceDefinition con los pasos mínimos que
  # Cadences::EnrollmentService#enroll! exige para poder inscribir una conversación
  # (steps_snapshot no puede quedar vacío).
  def create_cadence_definition!(inbox, is_default: true, segment_value: nil, name: 'Cadencia de prueba', steps: default_cadence_steps)
    cadence_definition = CadenceDefinition.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      name: name,
      segment_value: segment_value,
      is_default: is_default
    )

    create_step_definitions!(cadence_definition, steps)
    cadence_definition
  end

  def create_step_definitions!(cadence_definition, steps)
    steps.each_with_index do |attrs, index|
      CadenceStepDefinition.create!(
        {
          cadence_definition_id: cadence_definition.id,
          position: index + 1,
          template_key: "wa_step_#{index + 1}",
          template_name: "cadencia_paso_#{index + 1}",
          template_language: 'es_MX',
          wait_window_minutes: 15,
          creates_call_task: false
        }.merge(attrs)
      )
    end
  end

  # Alias usado por specs a los que solo les importa que el inbox tenga pasos configurados,
  # sin necesitar la CadenceDefinition resultante.
  def create_cadence_steps!(inbox, steps: default_cadence_steps)
    create_cadence_definition!(inbox, steps: steps)
  end

  def default_cadence_steps
    [
      { schedule_type: 'immediate', wait_window_minutes: 15, creates_call_task: true },
      { schedule_type: 'offset_from_last_step', offset_minutes: 300, wait_window_minutes: 120, creates_call_task: true },
      { schedule_type: 'day_offset_at_time', day_offset: 1, time_of_day: '09:00', wait_window_minutes: 180, creates_call_task: false }
    ]
  end

  # Construye un steps_snapshot "a mano" (sin pasar por CadenceStepDefinition) para specs
  # que crean el CadenceEnrollment directamente, sin pasar por EnrollmentService#enroll!.
  def cadence_step_snapshot(position, creates_call_task: true, **overrides)
    {
      'position' => position,
      'template_key' => "wa_step_#{position}",
      'template_name' => "cadencia_paso_#{position}",
      'template_language' => 'es_MX',
      'template_namespace' => nil,
      'schedule_type' => position == 1 ? 'immediate' : 'offset_from_last_step',
      'offset_minutes' => position == 1 ? nil : 60,
      'day_offset' => nil,
      'time_of_day' => nil,
      'wait_window_minutes' => 60,
      'creates_call_task' => creates_call_task,
      'media_url' => nil,
      'media_type' => nil,
      'media_name' => nil
    }.merge(overrides.stringify_keys)
  end

  def cadence_steps_snapshot(count: 6)
    (1..count).map { |position| cadence_step_snapshot(position, creates_call_task: position < count) }
  end
end

RSpec.configure do |config|
  config.include CadenceStepDefinitionsHelper
end
