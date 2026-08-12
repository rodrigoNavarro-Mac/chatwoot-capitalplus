class Api::V1::Accounts::CampaignsController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 25

  before_action :campaign, except: [:index, :create, :csv_usage_report, :csv_preview]
  before_action :check_authorization
  before_action :set_current_page, only: [:recipients]

  def index
    @campaigns = Current.account.campaigns
  end

  def show; end

  def metrics
    @metrics = Campaigns::CampaignMetricsBuilder.new(@campaign).build
  end

  def recipients
    scope = Campaigns::CampaignRecipientsFinder.new(@campaign, params).perform

    respond_to do |format|
      format.json do
        @recipients = scope.page(@current_page).per(RESULTS_PER_PAGE)
        @recipients_count = @recipients.total_count
      end
      format.csv do
        send_data generate_recipients_csv(scope), filename: recipients_csv_filename, type: 'text/csv; charset=utf-8'
      end
    end
  end

  def csv_usage_report
    @csv_usage_report = Campaigns::CsvUsageReportBuilder.new(Current.account).build
  end

  def csv_preview
    file = params[:csv_audience]
    return render json: { valid: false, errors: ['No se recibió ningún archivo'] } if file.blank?

    render json: Campaigns::CsvPreviewService.new(account: Current.account, file: file).build
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

  def set_current_page
    @current_page = params[:page] || 1
  end

  def generate_recipients_csv(scope)
    csv = CSV.generate do |rows|
      rows << ['Teléfono', 'Nombre', 'Estado', 'Enviado', 'Entregado', 'Leído', 'Motivo de falla', 'Respondió']
      scope.find_each(batch_size: 1000) do |delivery|
        rows << [
          delivery.phone_number,
          delivery.contact&.name || delivery.phone_number,
          delivery.status,
          delivery.sent_at,
          delivery.delivered_at,
          delivery.read_at,
          delivery.failed_reason,
          delivery.responded_at.present?
        ]
      end
    end

    "\xEF\xBB\xBF#{csv}"
  end

  def recipients_csv_filename
    "#{@campaign.title.parameterize}-destinatarios-#{Date.current.iso8601}.csv"
  end

  def campaign_params
    params.require(:campaign).permit(:title, :description, :message, :enabled, :trigger_only_during_business_hours, :inbox_id, :sender_id,
                                     :scheduled_at, :delay_min_seconds, :delay_max_seconds, :send_window_start, :send_window_end,
                                     :audience_type, :csv_audience,
                                     audience: [:type, :id], trigger_rules: {}, template_params: {})
  end
end
