# Groups WhatsApp CSV campaigns by the underlying file (via ActiveStorage checksum),
# so re-used spreadsheets can be compared across the campaigns sent from them.
class Campaigns::CsvUsageReportBuilder
  attr_reader :account

  def initialize(account)
    @account = account
  end

  def build
    rows = campaigns_with_csv.map { |campaign| campaign_row(campaign) }

    rows.group_by { |row| row[:checksum] }
        .map { |checksum, group| summarize(checksum, group) }
        .sort_by { |row| -row[:campaigns_count] }
  end

  private

  def campaigns_with_csv
    account.campaigns
           .where(audience_type: 'csv')
           .joins(:csv_audience_attachment)
           .includes(csv_audience_attachment: :blob)
  end

  def campaign_row(campaign)
    blob = campaign.csv_audience.blob
    {
      checksum: blob.checksum,
      filename: blob.filename.to_s,
      title: campaign.title,
      audience_count: campaign.audience_count.to_i,
      responded: campaign.campaign_message_deliveries.where.not(responded_at: nil).count
    }
  end

  def summarize(checksum, group)
    {
      checksum: checksum,
      filename: group.first[:filename],
      campaigns_count: group.size,
      campaign_titles: group.pluck(:title),
      total_audience_count: group.sum { |row| row[:audience_count] },
      total_responded: group.sum { |row| row[:responded] }
    }
  end
end
