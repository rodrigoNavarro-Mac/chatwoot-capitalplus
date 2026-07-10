# Calcula el próximo horario absoluto de un paso de la cadencia, en la zona horaria
# fija definida en Cadences::StepDefinitions::TIMEZONE. Todos los horarios se anclan
# a la fecha en que inició la cadencia (enrollment.created_at = momento de asignación).
class Cadences::ScheduleCalculator
  pattr_initialize [:enrollment!, :definition!]

  def next_run_at
    run_at =
      case definition[:schedule]
      when :immediate
        Time.current
      when :offset_from_enrollment
        (enrollment.last_template_sent_at || enrollment.created_at) + definition[:offset]
      when :next_day_at
        at_time(base_date + 1, definition[:at])
      when :day_n_at
        at_time(base_date + (definition[:day] - 1), definition[:at])
      end

    [run_at, Time.current].max
  end

  private

  def base_date
    enrollment.created_at.in_time_zone(Cadences::StepDefinitions::TIMEZONE).to_date
  end

  def at_time(date, hhmm)
    hour, minute = hhmm.split(':').map(&:to_i)
    ActiveSupport::TimeZone[Cadences::StepDefinitions::TIMEZONE].local(date.year, date.month, date.day, hour, minute)
  end
end
