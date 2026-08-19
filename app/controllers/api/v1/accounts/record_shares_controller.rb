class Api::V1::Accounts::RecordSharesController < Api::V1::Accounts::BaseController
  before_action :fetch_shareable, only: %i[index create]
  before_action :fetch_record_share, only: [:destroy]
  before_action :check_authorization

  def index
    @record_shares = @shareable.record_shares.order(created_at: :desc)
    render json: @record_shares.map { |share| share_json(share) }
  end

  def create
    @record_share = @shareable.record_shares.new(
      create_params.merge(account_id: Current.account.id, shared_by_id: Current.user.id)
    )
    @record_share.save!
    render json: share_json(@record_share)
  end

  def destroy
    @record_share.destroy!
    head :ok
  end

  private

  def fetch_shareable
    klass_name = params[:shareable_type].to_s
    return render json: { error: 'invalid_shareable_type' }, status: :unprocessable_entity unless RecordShare::SHAREABLE_TYPES.include?(klass_name)

    @shareable = Current.account.public_send(klass_name.underscore.pluralize).find_by(id: params[:shareable_id])
    render json: { error: 'not_found' }, status: :not_found unless @shareable
  end

  def fetch_record_share
    @record_share = RecordShare.where(account_id: Current.account.id).find_by(id: params[:id])
    render json: { error: 'not_found' }, status: :not_found unless @record_share
  end

  def check_authorization
    authorize(@record_share || @shareable.record_shares.build)
  end

  def create_params
    params.require(:record_share).permit(:shared_with_type, :shared_with_id, :access_level)
  end

  def share_json(share)
    {
      id: share.id,
      shareable_type: share.shareable_type,
      shareable_id: share.shareable_id,
      shared_with_type: share.shared_with_type,
      shared_with_id: share.shared_with_id,
      shared_with_name: share.shared_with.try(:name),
      access_level: share.access_level,
      shared_by_id: share.shared_by_id,
      shared_by_name: share.shared_by&.name,
      created_at: share.created_at
    }
  end
end
