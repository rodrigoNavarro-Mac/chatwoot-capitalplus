class Campaigns::CampaignRecipientsFinder
  ALLOWED_STATUSES = CampaignMessageDelivery.statuses.keys.freeze

  def initialize(campaign, params)
    @campaign = campaign
    @params = params
  end

  def perform
    scope = @campaign.campaign_message_deliveries.includes(:contact)
    scope = filter_by_status(scope)
    scope = filter_by_responded(scope)
    scope = filter_by_query(scope)
    scope.order(id: :asc)
  end

  private

  def filter_by_status(scope)
    status = @params[:status].to_s
    return scope unless ALLOWED_STATUSES.include?(status)

    scope.where(status: status)
  end

  def filter_by_responded(scope)
    case @params[:responded]
    when 'true' then scope.where.not(responded_at: nil)
    when 'false' then scope.where(responded_at: nil)
    else scope
    end
  end

  def filter_by_query(scope)
    return scope if @params[:q].blank?

    sanitized = "%#{@params[:q].strip}%"
    scope.left_joins(:contact).where(
      'campaign_message_deliveries.phone_number ILIKE :q OR campaign_message_deliveries.contact_name ILIKE :q OR contacts.name ILIKE :q',
      q: sanitized
    )
  end
end
