# Calcula el próximo horario absoluto de un paso de la cadencia. Todos los tipos de
# schedule anclan en el momento en que se envió la última plantilla (o el enrollment,
# si aún no se ha enviado ninguna): el conteo siempre representa "inactividad desde el
# último contacto", nunca una fecha fija de inscripción.
class Cadences::ScheduleCalculator
  TIMEZONE = 'America/Mexico_City'.freeze

  pattr_initialize [:enrollment!, :definition!]

  def next_run_at
    run_at =
      case definition[:schedule_type]
      when 'immediate'
        Time.current
      when 'offset_from_last_step'
        anchor_time + definition[:offset_minutes].minutes
      when 'day_offset_at_time'
        at_time(anchor_time.in_time_zone(TIMEZONE).to_date + definition[:day_offset], definition[:time_of_day])
      end

    [run_at, Time.current].max
  end

  private

  def anchor_time
    enrollment.last_template_sent_at || enrollment.created_at
  end

  def at_time(date, hhmm)
    hour, minute = hhmm.split(':').map(&:to_i)
    ActiveSupport::TimeZone[TIMEZONE].local(date.year, date.month, date.day, hour, minute)
  end
end
