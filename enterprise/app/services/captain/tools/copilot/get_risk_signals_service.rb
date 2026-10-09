class Captain::Tools::Copilot::GetRiskSignalsService < Captain::Tools::BaseTool
  include Captain::Tools::Copilot::ReportFormatting

  SIGNAL_TYPES = %w[deal_stalled lead_no_contact appointment_no_show_unverified].freeze
  SEVERITIES = %w[low medium high].freeze

  def self.name
    'get_risk_signals'
  end

  description 'Get open risk signals (stalled deals, leads with no contact, unverified appointment no-shows)'
  param :signal_type, type: :string, desc: "Filter by signal type: #{SIGNAL_TYPES.join(', ')}"
  param :severity, type: :string, desc: "Filter by severity: #{SEVERITIES.join(', ')}"
  param :desarrollo, type: :string, desc: 'Filter by desarrollo (development) name'

  def execute(signal_type: nil, severity: nil, desarrollo: nil)
    signals = @assistant.account.revenue_risk_signals.open.where(category: 'risk')
    signals = signals.where(signal_type: signal_type) if SIGNAL_TYPES.include?(signal_type)
    signals = signals.where(severity: severity) if SEVERITIES.include?(severity)

    rows = signals.filter_map { |signal| row_for(signal, desarrollo) }
    return not_found_message('risk signals') if rows.blank?

    <<~RESPONSE
      Total open risk signals: #{rows.length}
      #{format_rows(rows) { |row| row }}
    RESPONSE
  end

  def active?
    admin?
  end

  private

  def row_for(signal, desarrollo_filter)
    subject = signal.subject_type.safe_constantize&.find_by(id: signal.subject_id)
    return nil if subject.nil?

    subject_desarrollo = desarrollo_for(subject)
    return nil if desarrollo_filter.present? && subject_desarrollo != desarrollo_filter

    <<~ROW.strip
      Type: #{signal.signal_type}
      Severity: #{signal.severity}
      Desarrollo: #{subject_desarrollo || 'N/A'}
      Detail: #{detail_for(signal, subject)}
      First detected: #{signal.first_detected_at}
    ROW
  end

  def desarrollo_for(subject)
    return subject.desarrollo if subject.respond_to?(:desarrollo)
    return subject.revenue_deal&.desarrollo if subject.respond_to?(:revenue_deal)

    nil
  end

  def detail_for(signal, subject)
    case signal.signal_type
    when 'deal_stalled'
      "Deal '#{subject.try(:name)}' stalled #{signal.context['days_stalled']} days in stage '#{signal.context['stage']}'"
    when 'lead_no_contact'
      "Lead created #{signal.context['hours_since_created']} hours ago with no contact attempt"
    when 'appointment_no_show_unverified'
      "Appointment '#{subject.try(:subject)}' #{signal.context['hours_since_appointment']} hours ago without a verified visit"
    else
      signal.context.to_s
    end
  end
end
