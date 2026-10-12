class Captain::Tools::Copilot::GetLeadDiscardReasonsService < Captain::Tools::BaseTool
  include Captain::Tools::Copilot::ReportFormatting

  PERIODS = %w[this_week last_week this_month last_month].freeze

  def self.name
    'get_lead_discard_reasons'
  end

  description 'Get the breakdown of discard reasons for leads created within a date range (defaults to the current month)'
  param :period, type: :string, desc: "Relative period, one of: #{PERIODS.join(', ')}. Takes priority over since/until when given."
  param :since, type: :string, desc: 'Start date (YYYY-MM-DD), inclusive. Use together with until_date for a custom range.'
  param :until_date, type: :string, desc: 'End date (YYYY-MM-DD), inclusive. Use together with since for a custom range.'
  param :desarrollo, type: :string, desc: 'Filter by desarrollo (development) name'

  def execute(period: nil, since: nil, until_date: nil, desarrollo: nil)
    return "period must be one of: #{PERIODS.join(', ')}" if period.present? && PERIODS.exclude?(period)

    range = resolve_range(period, since, until_date)
    return 'since/until_date must be valid dates in YYYY-MM-DD format' if range.nil?

    leads = @assistant.account.revenue_leads.where(lead_status: RevenueIntelligence::LeadMapper::DISCARDED_LEAD_STATUSES,
                                                   created_at_source: day_range(range))
    leads = leads.where(desarrollo: desarrollo) if desarrollo.present?
    return not_found_message('discarded leads for that period') if leads.none?

    counts = tally_reasons(leads)

    <<~RESPONSE
      Period: #{range.begin} to #{range.end}
      Total discarded leads: #{counts.values.sum}
      #{format_rows(counts.sort_by { |_reason, count| -count }) { |reason, count| "#{reason}: #{count}" }}
    RESPONSE
  end

  def active?
    admin?
  end

  private

  def resolve_range(period, since, until_date)
    return relative_range(period) if period.present?
    return relative_range('this_month') if since.blank? || until_date.blank?

    Date.iso8601(since)..Date.iso8601(until_date)
  rescue ArgumentError, TypeError
    nil
  end

  def relative_range(period)
    today = Time.current.in_time_zone(RevenueIntelligence::TIMEZONE).to_date

    case period
    when 'this_week' then today.all_week
    when 'last_week' then (today - 1.week).all_week
    when 'this_month' then today.all_month
    when 'last_month' then (today - 1.month).all_month
    end
  end

  def day_range(date_range)
    start = date_range.begin.in_time_zone(RevenueIntelligence::TIMEZONE).beginning_of_day
    finish = date_range.end.in_time_zone(RevenueIntelligence::TIMEZONE).end_of_day
    start..finish
  end

  def tally_reasons(leads)
    leads.pluck(:discard_reason).each_with_object(Hash.new(0)) do |reason, tally|
      tally[reason.presence || V2::Reports::ZohoLeadsMetrics::UNSPECIFIED_DISCARD_REASON] += 1
    end
  end
end
