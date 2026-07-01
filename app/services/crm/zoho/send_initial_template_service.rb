class Crm::Zoho::SendInitialTemplateService
  def initialize(account, params)
    @account           = account
    @phone             = params[:phone].to_s.gsub(/\D/, '')
    @contact_name      = params[:contact_name].to_s.strip
    @desarrollo        = params[:desarrollo].to_s.strip
    @template_name     = params[:template_name].to_s.strip
    @template_language = params[:template_language].to_s.strip
    @body_params       = Array(params[:body_params])
  end

  def perform
    raise 'phone_required' if @phone.blank?
    raise 'desarrollo_required' if @desarrollo.blank?
    raise 'template_name_required' if @template_name.blank?

    inbox = find_inbox!

    ContactInboxWithContactBuilder.new(
      inbox: inbox,
      contact_attributes: {
        name:         @contact_name.presence || @phone,
        phone_number: "+#{@phone}"
      },
      source_id: @phone
    ).perform

    channel = inbox.channel
    name, namespace, lang_code, parameters = build_template_info(channel)
    channel.send_template("+#{@phone}", { name: name, namespace: namespace, lang_code: lang_code, parameters: parameters }, nil)
    Rails.logger.info("[ZohoCRM][SendTemplate] Sent '#{@template_name}' to +#{@phone} via inbox ##{inbox.id}")
  end

  private

  def find_inbox!
    inbox = @account.inboxes
                    .where(channel_type: 'Channel::Whatsapp')
                    .joins(agent_bot_inbox: :agent_bot)
                    .find { |i| i.agent_bot&.bot_config&.dig('variables', 'desarrollo') == @desarrollo }
    raise 'inbox_not_found' unless inbox

    inbox
  end

  def build_template_info(channel)
    body_map = @body_params.each_with_index.each_with_object({}) { |(val, i), h| h[(i + 1).to_s] = val }

    template_params = {
      'name'             => @template_name,
      'language'         => @template_language,
      'processed_params' => { 'body' => body_map }
    }

    Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: template_params
    ).call
  end
end
