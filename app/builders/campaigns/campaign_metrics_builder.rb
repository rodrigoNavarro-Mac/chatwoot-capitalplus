class Campaigns::CampaignMetricsBuilder
  attr_reader :campaign

  def initialize(campaign)
    @campaign = campaign
  end

  def build
    deliveries = campaign.campaign_message_deliveries

    {
      audience_count: campaign.audience_count,
      attempted: deliveries.count,
      **funnel_counts(deliveries),
      failed_reasons: deliveries.where(status: 'failed').group(:failed_reason).count,
      response_rate: response_rate(deliveries),
      variants: variants(deliveries),
      progress: Campaigns::CampaignProgressEstimator.new(campaign).build
    }
  end

  private

  def funnel_counts(deliveries)
    {
      sent: deliveries.where.not(sent_at: nil).count,
      delivered: deliveries.where.not(delivered_at: nil).count,
      read: deliveries.where.not(read_at: nil).count,
      failed: deliveries.where(status: 'failed').count,
      responded: deliveries.where.not(responded_at: nil).count
    }
  end

  # Side-by-side numbers for an A/B test campaign; nil when the campaign uses a single template
  def variants(deliveries)
    return unless Campaigns::TemplateVariantPicker.ab_test?(campaign)

    {
      'A' => variant_metrics(deliveries.where(template_variant: 'A'), campaign.template_params),
      'B' => variant_metrics(deliveries.where(template_variant: 'B'), campaign.template_variant_b['template_params'])
    }
  end

  def variant_metrics(deliveries, template_params)
    {
      template_name: template_params&.dig('name'),
      attempted: deliveries.count,
      **funnel_counts(deliveries),
      response_rate: response_rate(deliveries)
    }
  end

  def response_rate(deliveries)
    sent_count = deliveries.where.not(sent_at: nil).count
    return 0.0 if sent_count.zero?

    (deliveries.where.not(responded_at: nil).count.to_f / sent_count * 100).round(2)
  end
end
