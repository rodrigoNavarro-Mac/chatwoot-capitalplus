# Thin client for Meta's WhatsApp Message Template Analytics API, used to cross-check
# Chatwoot's own campaign delivery counts against what Meta actually reports.
#
# NOTE: the exact request/response shape here was assembled from indirect documentation
# (the official Meta docs page for this endpoint returned 404 when checked, and this class
# has not been exercised against a real WABA). Verify it against production credentials —
# e.g. via `Whatsapp::TemplateAnalyticsClient.new(...).fetch(...)` in a rails console — before
# relying on Campaigns::MetaAnalyticsReconciler's output.
class Whatsapp::TemplateAnalyticsClient
  BASE_URI = 'https://graph.facebook.com'.freeze
  METRIC_TYPES = %w[SENT DELIVERED READ CLICKED].freeze
  MAX_TEMPLATE_IDS = 10

  def initialize(waba_id:, access_token:)
    @waba_id = waba_id
    @access_token = access_token
    @api_version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
  end

  # Returns { "<template_id>" => { sent:, delivered:, read:, clicked: } } summed over the
  # date range. Raises on an HTTP failure or an unrecognized response shape — callers should
  # rescue rather than assume a successful call always yields usable data.
  def fetch(template_ids:, start_time:, end_time:)
    raise ArgumentError, 'template_ids must not be empty' if template_ids.blank?
    raise ArgumentError, "template_ids supports a maximum of #{MAX_TEMPLATE_IDS} ids per request" if template_ids.size > MAX_TEMPLATE_IDS

    response = HTTParty.get("#{BASE_URI}/#{@api_version}/#{@waba_id}", query: query_params(template_ids, start_time, end_time))
    raise "Meta template_analytics request failed (#{response.code}): #{response.body}" unless response.success?

    parse(response.parsed_response)
  end

  private

  def query_params(template_ids, start_time, end_time)
    fields = "template_analytics.start(#{start_time.to_i}).end(#{end_time.to_i}).granularity(DAILY)" \
             ".template_ids(#{template_ids.map(&:to_s).to_json}).metric_types(#{METRIC_TYPES.to_json})"
    { fields: fields, access_token: @access_token }
  end

  def parse(body)
    entries = body.dig('template_analytics', 'data')
    raise "Unexpected template_analytics response shape: #{body.to_json}" if entries.nil?

    data_points = entries.flat_map { |entry| entry['data_points'] || [] }
    data_points.each_with_object(Hash.new { |h, k| h[k] = { sent: 0, delivered: 0, read: 0, clicked: 0 } }) do |point, totals|
      accumulate(totals, point)
    end
  end

  def accumulate(totals, point)
    id = point['template_id'].to_s
    totals[id][:sent] += point['sent'].to_i
    totals[id][:delivered] += point['delivered'].to_i
    totals[id][:read] += point['read'].to_i
    totals[id][:clicked] += Array(point['clicked']).sum { |c| c['count'].to_i }
  end
end
