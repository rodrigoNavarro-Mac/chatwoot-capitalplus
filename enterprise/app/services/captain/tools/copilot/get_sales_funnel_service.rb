class Captain::Tools::Copilot::GetSalesFunnelService < Captain::Tools::BaseTool
  include Captain::Tools::Copilot::ReportFormatting

  def self.name
    'get_sales_funnel'
  end

  description 'Get the sales funnel (lead_created to closed_won) status for a desarrollo (development), actual vs target'
  param :desarrollo, type: :string, desc: 'The desarrollo (development) name. Omit to get all desarrollos.'

  def execute(desarrollo: nil)
    rows = V2::Reports::SalesFunnelBuilder.new(account: @assistant.account, params: { desarrollo: desarrollo }.compact).build
    return not_found_message('sales funnel data') if rows.blank?

    format_rows(rows) { |row| format_development(row) }
  end

  def active?
    admin?
  end

  private

  def format_development(row)
    <<~DEVELOPMENT.strip
      Desarrollo: #{row[:development_key]}
      #{format_rows(row[:stages]) { |stage| format_stage(stage) }}
      Aircall calls: #{row[:calls][:total]} total, #{row[:calls][:answered]} answered (#{format_percent(row[:calls][:answered_percent])})
    DEVELOPMENT
  end

  def format_stage(stage)
    target = stage[:target_percent].nil? ? 'no target set' : "target #{format_percent(stage[:target_percent])}, delta #{stage[:delta]}"
    "  - #{stage[:stage]}: #{stage[:count]} (#{format_percent(stage[:actual_percent])}, #{target})"
  end
end
