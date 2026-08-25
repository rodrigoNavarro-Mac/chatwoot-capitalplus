class Api::V1::Accounts::AgentBotsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :agent_bot, except: [:index, :create]

  def index
    @agent_bots = AgentBot.accessible_to(Current.account)
  end

  def show; end

  def create
    @agent_bot = Current.account.agent_bots.create!(permitted_params.except(:avatar_url))
    process_avatar_from_url
  end

  def update
    @agent_bot.update!(permitted_params.except(:avatar_url))
    process_avatar_from_url
  end

  def avatar
    @agent_bot.avatar.purge if @agent_bot.avatar.attached?
    @agent_bot
  end

  def destroy
    @agent_bot.destroy!
    head :ok
  end

  def reset_access_token
    @agent_bot.access_token.regenerate_token
    @agent_bot.reload
  end

  def reset_secret
    @agent_bot.reset_secret!
  end

  private

  def agent_bot
    @agent_bot = AgentBot.accessible_to(Current.account).find(params[:id]) if params[:action] == 'show'
    @agent_bot ||= Current.account.agent_bots.find(params[:id])
  end

  def permitted_params
    p = params.permit(:name, :description, :outgoing_url, :avatar, :avatar_url, :bot_type, :bot_config, bot_config: {})
    if params[:bot_config].is_a?(String)
      begin
        p[:bot_config] = JSON.parse(params[:bot_config])
      rescue JSON::ParserError
        p.delete(:bot_config)
      end
    end
    p
  end

  def process_avatar_from_url
    ::Avatar::AvatarFromUrlJob.perform_later(@agent_bot, params[:avatar_url]) if params[:avatar_url].present?
  end
end
