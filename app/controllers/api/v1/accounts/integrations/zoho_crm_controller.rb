class Api::V1::Accounts::Integrations::ZohoCrmController < Api::V1::Accounts::BaseController
  # Mapeo de atributos de conversación (Chatwoot) → campos de Lead en Zoho
  ZOHO_LEAD_FIELD_MAP = {
    'razon_compra' => 'Raz_n_de_compra',
    'plazo'        => 'Tiempo_de_inversi_n',
    'presupuesto'  => 'Presupuesto',
    'desarrollo'   => 'Desarrollo',
    'genero'       => 'G_nero',
    'ocupacion'    => 'Ocupaci_n',
    'estado_civil' => 'Estado_civil',
    'etapa_vida'   => 'Etapa_de_vida',
    'nacionalidad' => 'Nacionalidad',
    'rango_edad'   => 'Rango_de_edad'
  }.freeze

  # Mapeo para Deal
  ZOHO_DEAL_FIELD_MAP = {
    'plazo'       => 'Plazos',
    'presupuesto' => 'Amount',
    'desarrollo'  => 'Desarollo'
  }.freeze
  before_action :fetch_hook
  before_action :load_contact
  before_action :require_zoho_link, only: %i[contact_data update_stage create_crm_note create_deal push_to_crm]

  def contact_data
    rec = fetch_record
    render json: {
      zoho_module:       @zoho_module,
      zoho_record_url:   zoho_record_url,
      record_exists:     rec.present?,
      record:            rec,
      stage_options:     fetch_stage_options,
      conversation_data: fetch_conversation_data(params[:conversation_id]),
      notes:             fetch_notes,
      tasks:             fetch_tasks,
      meetings:          fetch_meetings
    }
  end

  def create_lead
    conv_attrs  = raw_conv_attrs(params[:conversation_id])
    existing    = search_zoho_by_phone(@contact.phone_number)
    zoho_id     = existing&.dig('id')
    zoho_module = existing&.dig('_module') || 'Leads'

    if zoho_id
      # Vincular existente y actualizar campos mapeados
      mapped = map_to_zoho_fields(conv_attrs, ZOHO_LEAD_FIELD_MAP)
      if mapped.any?
        Crm::Zoho::Api::BaseClient.new(@hook).put(
          "#{zoho_module}/#{zoho_id}",
          { data: [{ 'id' => zoho_id }.merge(mapped)] }
        )
      end
    else
      name_parts = @contact.name.to_s.split(' ', 2)
      lead_data  = {
        'Last_Name'   => name_parts.last.presence || @contact.name,
        'First_Name'  => name_parts.first,
        'Mobile'      => @contact.phone_number,
        'Email'       => @contact.email,
        'Lead_Source' => 'WhatsApp'
      }.compact

      lead_data.merge!(map_to_zoho_fields(conv_attrs, ZOHO_LEAD_FIELD_MAP))

      response    = Crm::Zoho::Api::BaseClient.new(@hook).post('Leads', { data: [lead_data] })
      zoho_id     = response.dig('data', 0, 'details', 'id')
      zoho_module = 'Leads'
    end

    return render json: { error: 'create_failed' }, status: :unprocessable_entity unless zoho_id

    ext_attrs = (@contact.additional_attributes || {}).deep_dup
    ext_attrs['external'] ||= {}
    ext_attrs['external']['zoho_id']     = zoho_id
    ext_attrs['external']['zoho_module'] = zoho_module
    @contact.update!(additional_attributes: ext_attrs)

    push_conversation_note(zoho_id, zoho_module, params[:conversation_id])

    render json: { zoho_id: zoho_id, zoho_module: zoho_module, linked_existing: existing.present? }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def create_deal
    deal_name    = params[:deal_name].presence || @contact.name
    stage        = params[:stage].presence || 'Qualification'
    closing_date = params[:closing_date].presence || 30.days.from_now.strftime('%Y-%m-%d')

    deal_data = {
      Deal_Name:    deal_name,
      Stage:        stage,
      Closing_Date: closing_date,
      Contact_Name: { id: @zoho_id }
    }

    response = Crm::Zoho::Api::BaseClient.new(@hook).post('Deals', { data: [deal_data] })
    deal_id  = response.dig('data', 0, 'details', 'id')

    return render json: { error: 'create_failed' }, status: :unprocessable_entity unless deal_id

    persist_deal_link(deal_id, stage)

    render json: { deal_id: deal_id, deal_name: deal_name }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def push_to_crm
    conv_attrs = raw_conv_attrs(params[:conversation_id])
    mapped     = map_to_zoho_fields(conv_attrs, ZOHO_LEAD_FIELD_MAP)

    return render json: { error: 'no_data' }, status: :unprocessable_entity if mapped.empty?

    Crm::Zoho::Api::BaseClient.new(@hook).put(
      "#{@zoho_module}/#{@zoho_id}",
      { data: [{ 'id' => @zoho_id }.merge(mapped)] }
    )
    render json: { success: true, fields_updated: mapped.keys }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update_stage
    field = @zoho_module == 'Deals' ? 'Stage' : 'Lead_Status'
    Crm::Zoho::Api::BaseClient.new(@hook).put(
      "#{@zoho_module}/#{@zoho_id}",
      { data: [{ 'id' => @zoho_id, field => params[:stage] }] }
    )
    render json: { success: true }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def create_crm_note
    Crm::Zoho::Api::NotesClient.new(@hook).create(
      zoho_id:     @zoho_id,
      zoho_module: @zoho_module,
      title:       params[:title].presence || 'Nota desde Chatwoot',
      content:     params[:content].to_s
    )
    render json: { success: true }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def fetch_hook
    @hook = Integrations::Hook.find_by(account: Current.account, app_id: 'zoho_crm', status: 'enabled')
    render json: { error: 'not_connected' }, status: :not_found and return unless @hook
  end

  def load_contact
    @contact = Current.account.contacts.find_by(id: params[:contact_id])
    render json: { error: 'not_found' }, status: :not_found and return unless @contact
  end

  def require_zoho_link
    ext          = @contact.additional_attributes&.dig('external')
    @zoho_id     = ext&.dig('zoho_id')
    @zoho_module = ext&.dig('zoho_module').presence || 'Leads'
    render json: { error: 'not_linked' }, status: :not_found and return unless @zoho_id
  end

  # Cachea localmente el deal vinculado al contacto (Crm::Zoho::DealsSyncJob refresca este
  # mismo par de claves periódicamente para reflejar cambios hechos directamente en Zoho).
  def persist_deal_link(deal_id, stage)
    ext_attrs = (@contact.additional_attributes || {}).deep_dup
    ext_attrs['external'] ||= {}
    ext_attrs['external']['zoho_deal_id']        = deal_id
    ext_attrs['external']['zoho_deal_stage']     = stage
    ext_attrs['external']['zoho_deal_synced_at'] = Time.current.iso8601
    @contact.update!(additional_attributes: ext_attrs)
  end

  def raw_conv_attrs(conversation_id)
    attrs = @contact.custom_attributes.reject { |k, _| k.to_s.start_with?('_') }

    if conversation_id.present?
      conversation = Current.account.conversations.find_by(id: conversation_id)
      if conversation
        # Variables estáticas del bot (desarrollo, ciudad, etc.) — menor prioridad
        bot_vars = bot_variables_for(conversation)
        attrs = bot_vars.merge(attrs)

        conv = conversation.custom_attributes.reject { |k, _| k.to_s.start_with?('_') }
        attrs = attrs.merge(conv)
      end
    end

    attrs
  rescue StandardError
    {}
  end

  def bot_variables_for(conversation)
    agent_bot = conversation.inbox&.agent_bot
    return {} unless agent_bot

    (agent_bot.bot_config&.dig('variables') || {}).stringify_keys
  rescue StandardError
    {}
  end

  def map_to_zoho_fields(attrs, mapping)
    attrs.each_with_object({}) do |(key, value), hash|
      zoho_key = mapping[key.to_s]
      hash[zoho_key] = value.to_s if zoho_key && value.present?
    end
  end

  def fetch_conversation_data(conversation_id)
    contact_attrs = @contact.custom_attributes.reject { |k, _| k.to_s.start_with?('_') }

    bot_attrs  = {}
    conv_attrs = {}
    if conversation_id.present?
      conversation = Current.account.conversations.find_by(id: conversation_id)
      if conversation
        bot_attrs  = bot_variables_for(conversation).select { |k, _| ZOHO_LEAD_FIELD_MAP.key?(k) || ZOHO_DEAL_FIELD_MAP.key?(k) }
        conv_attrs = (conversation.custom_attributes || {}).reject { |k, _| k.to_s.start_with?('_') }
      end
    end

    all_attrs = bot_attrs.merge(contact_attrs).merge(conv_attrs)
    return [] if all_attrs.blank?

    definitions = Current.account.custom_attribute_definitions
                         .where(attribute_model: %w[conversation_attribute contact_attribute],
                                attribute_key: all_attrs.keys)
                         .index_by(&:attribute_key)

    all_attrs.filter_map do |key, value|
      next if value.blank?
      { label: definitions[key]&.attribute_display_name || key.humanize, value: value.to_s }
    end
  rescue StandardError
    []
  end

  def push_conversation_note(zoho_id, zoho_module, conversation_id)
    data = fetch_conversation_data(conversation_id)
    return if data.empty?

    content = data.map { |d| "• #{d[:label]}: #{d[:value]}" }.join("\n")
    Crm::Zoho::Api::NotesClient.new(@hook).create(
      zoho_id:     zoho_id,
      zoho_module: zoho_module,
      title:       'Datos capturados por bot',
      content:     content
    )
  rescue StandardError
    nil
  end

  def zoho_record_url
    datacenter  = @hook.settings['datacenter'].presence || 'com'
    module_path = { 'Leads' => 'Leads', 'Deals' => 'Potentials', 'Contacts' => 'Contacts' }[@zoho_module]
    return nil unless module_path

    org_key = fetch_or_cache_org_key
    return nil unless org_key

    "https://crm.zoho.#{datacenter}/crm/#{org_key}/tab/#{module_path}/#{@zoho_id}"
  end

  def fetch_or_cache_org_key
    cached = @hook.settings['zoho_org_key']
    return cached if cached.present?

    response = Crm::Zoho::Api::BaseClient.new(@hook).get('org')
    zgid     = response.dig('org', 0, 'zgid')
    return nil unless zgid

    org_key = "org#{zgid}"
    @hook.update_columns(settings: @hook.settings.merge('zoho_org_key' => org_key))
    org_key
  rescue StandardError
    nil
  end

  def fetch_record
    response = Crm::Zoho::Api::BaseClient.new(@hook).get("#{@zoho_module}/#{@zoho_id}")
    Array(response['data']).first || {}
  rescue StandardError
    {}
  end

  # Busca en Leads y Contacts por teléfono (Mobile y Phone) para evitar duplicados
  def search_zoho_by_phone(phone)
    return nil unless phone.present?

    client = Crm::Zoho::Api::BaseClient.new(@hook)
    %w[Leads Contacts].each do |mod|
      %w[Mobile Phone].each do |field|
        response = client.get("#{mod}/search", criteria: "(#{field}:equals:#{phone})")
        record   = Array(response['data']).first
        return record.merge('_module' => mod) if record
      rescue Crm::Zoho::Api::BaseClient::ApiError
        next
      end
    end
    nil
  end

  def fetch_stage_options
    field_name = @zoho_module == 'Deals' ? 'Stage' : 'Lead_Status'
    response   = Crm::Zoho::Api::BaseClient.new(@hook).get('settings/fields', module: @zoho_module)
    fields     = Array(response.is_a?(Hash) ? response['fields'] : nil)
    field      = fields.find { |f| f.is_a?(Hash) && f['api_name'] == field_name }
    return [] unless field

    Array(field['pick_list_values']).filter_map do |v|
      next unless v.is_a?(Hash)
      label = v['display_value'].presence || v['actual_value'].presence
      value = v['actual_value'].presence || v['display_value'].presence
      next unless label && value
      { label: label, value: value }
    end
  rescue StandardError
    []
  end

  def fetch_notes
    Crm::Zoho::Api::NotesClient.new(@hook)
                               .list(zoho_id: @zoho_id, zoho_module: @zoho_module)
                               .reject { |n| chatwoot_note?(n) }
  rescue StandardError
    []
  end

  def fetch_tasks
    Crm::Zoho::Api::TasksClient.new(@hook).list(zoho_id: @zoho_id, zoho_module: @zoho_module)
  rescue StandardError
    []
  end

  def fetch_meetings
    Crm::Zoho::Api::MeetingsClient.new(@hook).list(zoho_id: @zoho_id, zoho_module: @zoho_module)
  rescue StandardError
    []
  end

  def chatwoot_note?(note)
    title = note['Note_Title'].to_s
    title.start_with?('Chatwoot') || title.include?('WhatsApp') || title.include?('Conversation')
  end
end
