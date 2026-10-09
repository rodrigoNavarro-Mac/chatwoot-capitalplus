class Captain::Tools::Copilot::GetLeadDiscardReasonsService < Captain::Tools::BaseTool
  include Captain::Tools::Copilot::ReportFormatting

  def self.name
    'get_lead_discard_reasons'
  end

  description 'Get the breakdown of discard reasons for leads created in a given month'
  param :year, type: :integer, desc: 'The year, e.g. 2026', required: true
  param :month, type: :integer, desc: 'The month number, 1-12', required: true
  param :desarrollo, type: :string, desc: 'Filter by desarrollo (development) name'

  def execute(year:, month:, desarrollo: nil)
    return 'month must be between 1 and 12' unless (1..12).cover?(month)

    leads = @assistant.account.revenue_leads.where(lead_status: RevenueIntelligence::LeadMapper::DISCARDED_LEAD_STATUSES,
                                                   created_at_source: month_range(year, month))
    leads = leads.where(desarrollo: desarrollo) if desarrollo.present?
    return not_found_message('discarded leads for that period') if leads.none?

    counts = tally_reasons(leads)

    <<~RESPONSE
      Total discarded leads: #{counts.values.sum}
      #{format_rows(counts.sort_by { |_reason, count| -count }) { |reason, count| "#{reason}: #{count}" }}
    RESPONSE
  end

  def active?
    admin?
  end

  private

  def month_range(year, month)
    start = Date.new(year, month, 1).beginning_of_day
    start..start.end_of_month.end_of_day
  end

  def tally_reasons(leads)
    leads.pluck(:discard_reason).each_with_object(Hash.new(0)) do |reason, tally|
      tally[reason.presence || V2::Reports::ZohoLeadsMetrics::UNSPECIFIED_DISCARD_REASON] += 1
    end
  end
end
