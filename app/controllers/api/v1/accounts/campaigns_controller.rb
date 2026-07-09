class Api::V1::Accounts::CampaignsController < Api::V1::Accounts::BaseController
  before_action :campaign, except: [:index, :create, :csv_usage_report]
  before_action :check_authorization

  def index
    @campaigns = Current.account.campaigns
  end

  def show; end

  def metrics
    @metrics = Campaigns::CampaignMetricsBuilder.new(@campaign).build
  end

  def csv_usage_report
    @csv_usage_report = Campaigns::CsvUsageReportBuilder.new(Current.account).build
  end

  def create
    @campaign = Current.account.campaigns.create!(campaign_params)
  end

  def update
    @campaign.update!(campaign_params)
  end

  def destroy
    @campaign.destroy!
    head :ok
  end

  private

  def campaign
    @campaign ||= Current.account.campaigns.find_by(display_id: params[:id])
  end

  def campaign_params
    params.require(:campaign).permit(:title, :description, :message, :enabled, :trigger_only_during_business_hours, :inbox_id, :sender_id,
                                     :scheduled_at, :delay_min_seconds, :delay_max_seconds, :send_window_start, :send_window_end,
                                     :audience_type, :csv_audience,
                                     audience: [:type, :id], trigger_rules: {}, template_params: {})
  end
end
