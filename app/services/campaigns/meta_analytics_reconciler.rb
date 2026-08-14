# Compares Chatwoot's own campaign_message_delivery counts against what Meta reports for the
# template a campaign actually sent, so a future webhook-drop incident (like the one that left
# Cluster 777 showing 2 delivered when Meta had recorded 73) gets caught within a day instead of
# only surfacing when someone happens to compare the two dashboards by hand.
#
# Depends on Whatsapp::TemplateAnalyticsClient — see that class for the caveat about its request
# shape not having been verified against a real WABA yet.
class Campaigns::MetaAnalyticsReconciler
  MISMATCH_THRESHOLD = 0.2 # flag when Meta reports >20% more delivered/read than Chatwoot recorded
  METRICS = %i[sent delivered read].freeze

  pattr_initialize [:campaign!]

  def perform
    return if template_id.blank?

    meta_totals = fetch_meta_totals
    return log_no_data if meta_totals.blank?

    chatwoot_totals = chatwoot_counts
    discrepancies = build_discrepancies(meta_totals, chatwoot_totals)
    log_result(meta_totals, chatwoot_totals, discrepancies)
    discrepancies
  rescue StandardError => e
    Rails.logger.error "[MetaAnalyticsReconciliation] campaign #{campaign.id}: failed to reconcile - #{e.message}"
    nil
  end

  private

  def fetch_meta_totals
    analytics_client.fetch(template_ids: [template_id], start_time: range_start, end_time: range_end)[template_id.to_s]
  end

  def channel
    campaign.inbox.channel
  end

  def template_id
    return @template_id if defined?(@template_id)

    name = campaign.template_params&.dig('name')
    return @template_id = nil if name.blank?

    language = campaign.template_params&.dig('language')
    template = Array(channel.message_templates).find { |t| matches_template?(t, name, language) }
    @template_id = template && template['id']
  end

  def matches_template?(template, name, language)
    template['name'] == name && (language.blank? || template['language'].to_s.casecmp?(language.to_s))
  end

  def analytics_client
    Whatsapp::TemplateAnalyticsClient.new(
      waba_id: channel.provider_config['business_account_id'],
      access_token: channel.provider_config['api_key']
    )
  end

  def range_start
    (campaign.campaign_message_deliveries.minimum(:sent_at) || campaign.scheduled_at || campaign.created_at).beginning_of_day
  end

  def range_end
    [Time.current, range_start + 7.days].min
  end

  def chatwoot_counts
    deliveries = campaign.campaign_message_deliveries
    {
      sent: deliveries.where.not(source_id: nil).count,
      delivered: deliveries.where.not(delivered_at: nil).count,
      read: deliveries.where.not(read_at: nil).count
    }
  end

  def build_discrepancies(meta_totals, chatwoot_totals)
    METRICS.filter_map do |metric|
      meta_value = meta_totals[metric].to_i
      next if meta_value.zero?

      chatwoot_value = chatwoot_totals[metric].to_i
      gap_ratio = (meta_value - chatwoot_value).to_f / meta_value
      { metric: metric, meta: meta_value, chatwoot: chatwoot_value, gap_ratio: gap_ratio.round(2) } if gap_ratio > MISMATCH_THRESHOLD
    end
  end

  def log_result(meta_totals, chatwoot_totals, discrepancies)
    summary = "meta=#{meta_totals} chatwoot=#{chatwoot_totals}"
    if discrepancies.present?
      Rails.logger.error "[MetaAnalyticsReconciliation] campaign #{campaign.id} MISMATCH: #{summary} gaps=#{discrepancies}"
    else
      Rails.logger.info "[MetaAnalyticsReconciliation] campaign #{campaign.id} OK: #{summary}"
    end
  end

  def log_no_data
    Rails.logger.info "[MetaAnalyticsReconciliation] campaign #{campaign.id}: no analytics data returned by Meta for template #{template_id}"
    nil
  end
end
