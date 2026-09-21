# Tiempo TRANSCURRIDO entre dos timestamps, contando solo minutos dentro del horario laboral del
# inbox (WorkingHour) -- distinto de V2::Reports::BusinessHoursClassifier, que solo responde
# "¿este timestamp cae en horario laboral?" para UN instante, no calcula duración entre dos.
#
# Camina día por día (acotado: un lead sin contactar durante semanas genera a lo más un puñado de
# iteraciones, trivial al volumen de esta cuenta) intersectando la ventana abierta de cada día con
# [start_time, end_time] -- así un lead creado fuera de horario no empieza a acumular tiempo hasta
# el siguiente turno (sección 2.1 del brief de Marketing: lead a la 1am, turno arranca a las 9am,
# contacto a las 9:04am = 4 minutos, NO 8h4m).
class RevenueIntelligence::BusinessElapsedTimeCalculator
  def initialize(inbox)
    @inbox = inbox
    @working_hours_by_day = inbox.working_hours.index_by(&:day_of_week)
  end

  def elapsed_seconds(start_time, end_time)
    return 0 if start_time.blank? || end_time.blank? || end_time <= start_time

    zone = Time.find_zone!(inbox.timezone.presence || 'UTC')
    cursor = start_time.in_time_zone(zone)
    finish = end_time.in_time_zone(zone)
    total = 0

    while cursor < finish
      day_open, day_close = open_window_for(cursor)
      total += overlap_seconds(cursor, finish, day_open, day_close) if day_open.present?
      cursor = cursor.end_of_day + 1.second
    end

    total
  end

  private

  attr_reader :inbox, :working_hours_by_day

  def overlap_seconds(cursor, finish, day_open, day_close)
    segment_start = [cursor, day_open].max
    segment_end = [finish, day_close].min
    return 0 if segment_end <= segment_start

    (segment_end - segment_start).to_i
  end

  def open_window_for(time)
    working_hour = working_hours_by_day[time.wday]
    return [nil, nil] if working_hour.blank? || working_hour.closed_all_day?
    return [time.beginning_of_day, time.end_of_day] if working_hour.open_all_day?

    [time.change(hour: working_hour.open_hour, min: working_hour.open_minutes),
     time.change(hour: working_hour.close_hour, min: working_hour.close_minutes)]
  end
end
