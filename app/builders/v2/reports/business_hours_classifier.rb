# Responde "¿este timestamp cae dentro del horario laboral configurado del inbox?" — usado por
# V2::Reports::ZohoLeadsMetrics#schedule_distribution para clasificar leads de Zoho por su
# Created_Time.
#
# No existe nada reutilizable para esto en el resto del código: WorkingHour#open_at?
# (enterprise/../working_hour.rb) tiene un bug — arma open_time/close_time con la fecha de HOY sin
# importar la fecha del timestamp que se le pasa, así que solo sirve para "¿está abierto AHORA
# MISMO?" (open_now?), no para timestamps pasados arbitrarios. Este classifier sí resuelve el día
# de la semana real de cada timestamp (en el timezone del inbox) contra el WorkingHour de ESE día.
class V2::Reports::BusinessHoursClassifier
  def initialize(inbox)
    @inbox = inbox
    @working_hours_by_day = inbox.working_hours.index_by(&:day_of_week)
  end

  def within_business_hours?(time)
    return false if time.blank?

    local_time = time.in_time_zone(inbox.timezone)
    working_hour = working_hours_by_day[local_time.wday]
    return false if working_hour.blank? || working_hour.closed_all_day?
    return true if working_hour.open_all_day?

    minutes_of_day = (local_time.hour * 60) + local_time.min
    open_minutes = (working_hour.open_hour * 60) + working_hour.open_minutes
    close_minutes = (working_hour.close_hour * 60) + working_hour.close_minutes

    minutes_of_day.between?(open_minutes, close_minutes)
  end

  private

  attr_reader :inbox, :working_hours_by_day
end
