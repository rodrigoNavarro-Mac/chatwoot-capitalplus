class Captain::Tools::Copilot::GetWeeklyOpsReportSummaryService < Captain::Tools::BaseTool
  include Captain::Tools::Copilot::ReportFormatting

  def self.name
    'get_weekly_ops_report_summary'
  end

  description 'Get the executive summary of the latest already-generated Weekly Ops Report for a desarrollo (development)'
  param :desarrollo, type: :string, desc: 'The desarrollo (development) name', required: true

  def execute(desarrollo:)
    inbox_ids = @assistant.account.inboxes.includes(agent_bot_inbox: :agent_bot)
                          .select { |inbox| inbox.development_key == desarrollo }.map(&:id)
    return not_found_message("weekly ops report for desarrollo '#{desarrollo}'") if inbox_ids.blank?

    report = WeeklyOpsReport.where(inbox_id: inbox_ids).completed.recent_first.first
    return not_found_message("weekly ops report for desarrollo '#{desarrollo}'") if report.nil?

    <<~RESPONSE
      Desarrollo: #{desarrollo}
      Period: #{report.period_start} to #{report.period_end} (#{report.period_type})
      New conversations: #{report.kpis.dig('volume', 'new_conversations')}

      Executive summary:
      #{report.llm_analysis}
    RESPONSE
  end

  def active?
    admin?
  end
end
