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
      sent: deliveries.where.not(sent_at: nil).count,
      delivered: deliveries.where.not(delivered_at: nil).count,
      read: deliveries.where.not(read_at: nil).count,
      failed: deliveries.where(status: 'failed').count,
      failed_reasons: deliveries.where(status: 'failed').group(:failed_reason).count,
      responded: deliveries.where.not(responded_at: nil).count,
      response_rate: response_rate(deliveries)
    }
  end

  private

  def response_rate(deliveries)
    sent_count = deliveries.where.not(sent_at: nil).count
    return 0.0 if sent_count.zero?

    (deliveries.where.not(responded_at: nil).count.to_f / sent_count * 100).round(2)
  end
end
