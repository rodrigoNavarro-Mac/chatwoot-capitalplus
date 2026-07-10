module Cadences::StepDefinitions
  # Estructura fija de la cadencia comercial. No editable desde UI ni base de datos:
  # ajustar horarios/plantillas aquí implica un deploy, a propósito.
  TIMEZONE = 'America/Mexico_City'.freeze

  STEPS = [
    {
      step: 1,
      template_key: 'wa_primer_contacto',
      schedule: :immediate,
      wait_window: 15.minutes,
      creates_call_task: true
    },
    {
      step: 2,
      template_key: 'wa_segundo_intento',
      schedule: :offset_from_enrollment,
      offset: 5.hours,
      wait_window: 2.hours,
      creates_call_task: true
    },
    {
      step: 3,
      template_key: 'wa_dia_siguiente_temprano',
      schedule: :next_day_at,
      at: '09:00',
      wait_window: 3.hours,
      creates_call_task: true
    },
    {
      step: 4,
      template_key: 'wa_horario_comida',
      schedule: :next_day_at,
      at: '14:00',
      wait_window: 3.hours,
      creates_call_task: true
    },
    {
      step: 5,
      template_key: 'wa_dia_5_noche',
      schedule: :day_n_at,
      day: 5,
      at: '20:00',
      wait_window: 12.hours,
      creates_call_task: true
    },
    {
      step: 6,
      template_key: 'wa_recuperacion',
      schedule: :day_n_at,
      day: 15,
      at: '20:00',
      wait_window: 24.hours,
      creates_call_task: false,
      recovery_step: true
    }
  ].freeze

  def self.for_step(step)
    STEPS.find { |definition| definition[:step] == step }
  end

  def self.first
    STEPS.first
  end

  def self.after(step)
    STEPS.find { |definition| definition[:step] == step + 1 }
  end
end
