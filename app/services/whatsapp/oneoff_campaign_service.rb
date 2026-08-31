require 'csv'

class Whatsapp::OneoffCampaignService
  VirtualContact = Struct.new(:name, :phone_number, :email, :custom_attributes)

  pattr_initialize [:campaign!]

  def perform
    validate_campaign!
    if campaign.audience_type == 'csv'
      schedule_contacts_from_csv
    else
      schedule_contacts(extract_audience_labels)
    end
    campaign.completed!
  end

  # Called by Campaigns::SendCampaignContactJob (label-based) — returns WA message ID or nil
  def send_to_contact(contact)
    return if contact.phone_number.blank?
    return if campaign.template_params.blank?

    processed_template_params = process_liquid_template_params(contact)
    return if processed_template_params.nil?

    message = labels_message_builder.build(contact)
    return if message.nil?

    wa_message_id, send_error = send_whatsapp_template_message(
      to: contact.phone_number, template_params: processed_template_params, message: message
    )
    delivery_recorder.record_labels_delivery(contact: contact, message: message, wa_message_id: wa_message_id, send_error: send_error)
    wa_message_id
  rescue StandardError => e
    Rails.logger.error "Failed to send campaign #{campaign.id} to contact #{contact.try(:name)}: #{e.message}"
    nil
  end

  # Called by Campaigns::SendCampaignContactJob (CSV-based) — returns WA message ID or nil
  def send_to_csv_contact(contact_data)
    raw_phone = contact_data['phone_number'].presence || contact_data['phone'].presence
    return if raw_phone.blank?
    return if campaign.template_params.blank?

    phone = Whatsapp::CsvContactPhoneNormalizer.new(inbox: inbox).normalize(raw_phone)
    virtual_contact = build_virtual_contact(contact_data, phone)
    processed_template_params = process_liquid_template_params(virtual_contact)
    return if processed_template_params.nil?

    wa_message_id, send_error = send_whatsapp_template_message(to: phone, template_params: processed_template_params)
    delivery_recorder.record_csv_delivery(phone: phone, contact_name: virtual_contact.name, wa_message_id: wa_message_id, send_error: send_error)
    wa_message_id
  rescue StandardError => e
    Rails.logger.error "Failed to send CSV campaign #{campaign.id} to #{contact_data['phone_number']}: #{e.message}"
    nil
  end

  private

  delegate :inbox, to: :campaign
  delegate :channel, to: :inbox

  def validate_campaign_type!
    raise "Invalid campaign #{campaign.id}" unless whatsapp_campaign? && campaign.one_off?
  end

  def whatsapp_campaign?
    campaign.inbox.inbox_type == 'Whatsapp'
  end

  def validate_campaign_status!
    raise 'Completed Campaign' if campaign.completed?
  end

  def validate_provider!
    raise 'WhatsApp Cloud provider required' if channel.provider != 'whatsapp_cloud'
  end

  def validate_feature_flag!
    raise 'WhatsApp campaigns feature not enabled' unless campaign.account.feature_enabled?(:whatsapp_campaign)
  end

  def validate_campaign!
    validate_campaign_type!
    validate_campaign_status!
    validate_provider!
    validate_feature_flag!
  end

  def extract_audience_labels
    audience_label_ids = campaign.audience.select { |audience| audience['type'] == 'Label' }.pluck('id')
    campaign.account.labels.where(id: audience_label_ids).pluck(:title)
  end

  def schedule_contacts(audience_labels)
    contacts = campaign.account.contacts
                       .tagged_with(audience_labels, any: true)
                       .where("(additional_attributes->>'wa_valid') IS DISTINCT FROM 'false'")
    already_sent_contact_ids = load_already_sent_contact_ids

    campaign.update!(audience_count: contacts.count)
    Rails.logger.info "Scheduling #{contacts.count} contacts for campaign #{campaign.id}"

    current_time = advance_to_window(Time.current)
    contacts.each do |contact|
      next if already_sent_contact_ids.include?(contact.id)

      current_time = schedule_labeled_contact(contact, current_time)
    end

    Rails.logger.info "Campaign #{campaign.id}: last message scheduled at #{current_time}"
  end

  def schedule_labeled_contact(contact, current_time)
    Campaigns::SendCampaignContactJob.set(wait_until: current_time).perform_later(campaign.id, contact.id)
    advance_to_window(current_time + next_send_delay.seconds)
  end

  # rubocop:disable Metrics/AbcSize
  def schedule_contacts_from_csv
    unless campaign.csv_audience.attached?
      Rails.logger.error "Campaign #{campaign.id}: no CSV file attached, skipping scheduling"
      return
    end

    rows = parse_csv_rows
    invalid_phones = load_invalid_phones
    already_sent_phones = load_already_sent_phones

    campaign.update!(audience_count: rows.size)
    Rails.logger.info "Scheduling #{rows.size} CSV rows for campaign #{campaign.id}"

    current_time = advance_to_window(Time.current)
    rows.each do |row|
      current_time = schedule_csv_row(row, invalid_phones, already_sent_phones, current_time)
    end

    Rails.logger.info "Campaign #{campaign.id}: last CSV message scheduled at #{current_time}"
  end
  # rubocop:enable Metrics/AbcSize

  def schedule_csv_row(row, invalid_phones, already_sent_phones, current_time)
    raw_phone = row['phone_number'].presence || row['phone'].presence
    return current_time if raw_phone.blank?

    phone = Whatsapp::CsvContactPhoneNormalizer.new(inbox: inbox).normalize(raw_phone)
    return current_time if invalid_phones.include?(phone) || already_sent_phones.include?(phone)

    row_args = [campaign.id, nil, row.merge('phone_number' => phone, 'phone' => phone)]
    Campaigns::SendCampaignContactJob.set(wait_until: current_time).perform_later(*row_args)
    advance_to_window(current_time + next_send_delay.seconds)
  end

  def next_send_delay
    rand(campaign.delay_min_seconds..campaign.delay_max_seconds)
  end

  # A blank source_id means the send attempt never actually reached Meta (recorded as
  # 'failed' at send time), so those are safe to retry. Anything with a source_id already
  # went out as a real WhatsApp message and must not be sent again if the campaign gets
  # re-run (e.g. reactivated after being paused).
  def load_already_sent_phones
    campaign.campaign_message_deliveries.where(audience_type: 'csv').where.not(source_id: nil).pluck(:phone_number).to_set
  end

  def load_already_sent_contact_ids
    campaign.campaign_message_deliveries.where(audience_type: 'labels').where.not(source_id: nil).pluck(:contact_id).to_set
  end

  def parse_csv_rows
    raw = campaign.csv_audience.download         # ASCII-8BIT binary
    raw.sub!(/\A\xEF\xBB\xBF/n, '')            # strip UTF-8 BOM while still binary
    raw.force_encoding('UTF-8')
    raw = raw.encode('UTF-8', 'UTF-8', invalid: :replace, undef: :replace, replace: '') unless raw.valid_encoding?

    CSV.parse(raw, headers: true).map(&:to_h)
  rescue StandardError => e
    Rails.logger.error "Failed to parse CSV for campaign #{campaign.id}: #{e.message}"
    []
  end

  def load_invalid_phones
    key = format(Redis::RedisKeys::WA_INVALID_PHONES, account_id: campaign.account_id)
    Redis::Alfred.with { |conn| conn.smembers(key) }.to_set
  rescue StandardError
    Set.new
  end

  def build_virtual_contact(data, phone)
    reserved_keys = %w[phone_number phone name email]
    extra_attrs = data.reject { |k, _| reserved_keys.include?(k.to_s) }
    VirtualContact.new(
      data['name'].presence || phone,
      phone,
      data['email'],
      extra_attrs
    )
  end

  def advance_to_window(time)
    Campaigns::SendWindow.advance_to_window(campaign, time)
  end

  def process_liquid_template_params(contact)
    liquid_processor = Whatsapp::LiquidTemplateProcessorService.new(campaign: campaign, contact: contact)
    processed_template_params = liquid_processor.process_template_params(campaign.template_params)

    Rails.logger.info "Skipping #{contact.try(:phone_number)} — liquid variables resolved to blank" if processed_template_params.nil?

    processed_template_params
  rescue StandardError => e
    Rails.logger.error "Failed to process liquid template for #{contact.try(:phone_number)}: #{e.message}"
    nil
  end

  # Returns [wa_message_id, send_error] — send_error is only present when wa_message_id is nil
  def send_whatsapp_template_message(to:, template_params:, message: nil)
    processor = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: template_params
    )

    name, namespace, lang_code, processed_parameters = processor.call
    return [nil, nil] if name.blank?

    provider = channel.provider_service
    template_info = { name: name, namespace: namespace, lang_code: lang_code, parameters: processed_parameters }
    [provider.send_template(to, template_info, message), provider.last_send_error]
  rescue StandardError => e
    Rails.logger.error "Failed to send WhatsApp template to #{to}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    [nil, e.message]
  end

  def labels_message_builder
    @labels_message_builder ||= Campaigns::LabelsMessageBuilder.new(campaign: campaign)
  end

  def delivery_recorder
    @delivery_recorder ||= Campaigns::MessageDeliveryRecorder.new(campaign: campaign)
  end
end

Whatsapp::OneoffCampaignService.prepend_mod_with('Whatsapp::OneoffCampaignService')
