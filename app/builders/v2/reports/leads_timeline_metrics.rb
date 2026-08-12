# Bucketea leads de Zoho (ya traídos por Crm::Zoho::LeadsForPeriodService) por Created_Time, según
# la granularidad pedida (día/semana/mes) — usado por V2::Reports::WeeklyOpsReportBuilder para la
# gráfica "leads creados por periodo", cuya granularidad se adapta al tipo de reporte (semana → día,
# mes → semana, trimestre → mes). Incluye TODOS los buckets del rango aunque tengan 0 leads, para
# que la gráfica no quede con huecos.
class V2::Reports::LeadsTimelineMetrics
  DAY_LABEL_FORMAT = '%d/%m'.freeze
  MESES_ES = %w[ene feb mar abr may jun jul ago sep oct nov dic].freeze

  def initialize(leads:, range:, granularity:, account: nil)
    @leads = leads
    @range = range
    @granularity = granularity
    @account = account
  end

  def build
    starts = bucket_starts

    {
      granularity: granularity,
      labels: starts.map { |date| label_for(date) },
      counts: starts.map { |date| counts_by_bucket[date] || 0 },
      dates: starts.map(&:iso8601)
    }
  end

  private

  attr_reader :leads, :range, :granularity, :account

  def counts_by_bucket
    @counts_by_bucket ||= leads.filter_map { |lead| bucket_start_for(lead['Created_Time']) }.tally
  end

  def timezone
    @timezone ||= account&.reporting_timezone.presence || 'UTC'
  end

  # Time.zone.parse devuelve nil (no lanza) ante un string no parseable — el guard cubre ambos casos.
  def bucket_start_for(created_time)
    return nil if created_time.blank?

    parsed = Time.zone.parse(created_time)
    return nil if parsed.nil?

    truncate(parsed.in_time_zone(timezone).to_date)
  rescue ArgumentError
    nil
  end

  # Todas las fechas de inicio de bucket dentro del rango, en orden — incluye buckets sin leads.
  def bucket_starts
    return [] if range.blank?

    starts = []
    current = truncate(range.begin.to_date)
    last = truncate((range.end - 1.second).to_date)

    while current <= last
      starts << current
      current = advance(current)
    end

    starts
  end

  def truncate(date)
    case granularity
    when 'week' then date.beginning_of_week(:monday)
    when 'month' then date.beginning_of_month
    else date
    end
  end

  def advance(date)
    case granularity
    when 'week' then date + 1.week
    when 'month' then date.next_month
    else date + 1.day
    end
  end

  def label_for(date)
    case granularity
    when 'week' then "Sem. #{date.strftime(DAY_LABEL_FORMAT)}"
    when 'month' then "#{MESES_ES[date.month - 1]} #{date.year}"
    else date.strftime(DAY_LABEL_FORMAT)
    end
  end
end
