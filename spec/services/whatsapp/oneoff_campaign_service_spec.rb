require 'rails_helper'

describe Whatsapp::OneoffCampaignService do
  let(:account) { create(:account) }
  let!(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let!(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:label1) { create(:label, account: account) }
  let(:label2) { create(:label, account: account) }
  let!(:campaign) do
    create(:campaign, inbox: whatsapp_inbox, account: account,
                      audience: [{ type: 'Label', id: label1.id }, { type: 'Label', id: label2.id }],
                      template_params: template_params)
  end
  let(:template_params) do
    {
      'name' => 'ticket_status_updated',
      'namespace' => '23423423_2342423_324234234_2343224',
      'category' => 'UTILITY',
      'language' => 'en',
      'processed_params' => { 'body' => { 'name' => 'John', 'ticket_id' => '2332' } }
    }
  end

  before do
    # Stub HTTP requests to WhatsApp API
    stub_request(:post, /graph\.facebook\.com.*messages/)
      .to_return(status: 200, body: { messages: [{ id: 'message_id_123' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

    # Ensure the service uses our mocked channel object by stubbing the whole delegation chain
    # Using allow_any_instance_of here because the service is instantiated within individual tests
    # and we need to mock the delegated channel method for proper test isolation
    allow_any_instance_of(described_class).to receive(:channel).and_return(whatsapp_channel) # rubocop:disable RSpec/AnyInstance
  end

  describe '#perform' do
    before do
      # Enable WhatsApp campaigns feature flag for all tests
      account.enable_features!(:whatsapp_campaign)
    end

    context 'when campaign validation fails' do
      it 'raises error if campaign is completed' do
        campaign.completed!

        expect { described_class.new(campaign: campaign).perform }.to raise_error 'Completed Campaign'
      end

      it 'raises error when campaign is not a WhatsApp campaign' do
        sms_channel = create(:channel_sms, account: account)
        sms_inbox = create(:inbox, channel: sms_channel, account: account)
        invalid_campaign = create(:campaign, inbox: sms_inbox, account: account)

        expect { described_class.new(campaign: invalid_campaign).perform }
          .to raise_error "Invalid campaign #{invalid_campaign.id}"
      end

      it 'raises error when campaign is not oneoff' do
        allow(campaign).to receive(:one_off?).and_return(false)

        expect { described_class.new(campaign: campaign).perform }.to raise_error "Invalid campaign #{campaign.id}"
      end

      it 'raises error when channel provider is not whatsapp_cloud' do
        whatsapp_channel.update!(provider: 'default')

        expect { described_class.new(campaign: campaign).perform }.to raise_error 'WhatsApp Cloud provider required'
      end

      it 'raises error when WhatsApp campaigns feature is not enabled' do
        account.disable_features!(:whatsapp_campaign)

        expect { described_class.new(campaign: campaign).perform }.to raise_error 'WhatsApp campaigns feature not enabled'
      end
    end

    context 'when campaign is valid' do
      it 'marks campaign as completed' do
        described_class.new(campaign: campaign).perform

        expect(campaign.reload.completed?).to be true
      end

      it 'marks the campaign completed after processing the audience' do
        contact = create(:contact, :with_phone_number, account: account)
        contact.update_labels([label1.title])

        expect(whatsapp_channel).to receive(:send_template) do
          expect(campaign.reload.completed?).to be false
        end

        described_class.new(campaign: campaign).perform

        expect(campaign.reload.completed?).to be true
      end

      it 'processes contacts with matching labels' do
        contact_with_label1, contact_with_label2, contact_with_both_labels =
          create_list(:contact, 3, :with_phone_number, account: account)
        contact_with_label1.update_labels([label1.title])
        contact_with_label2.update_labels([label2.title])
        contact_with_both_labels.update_labels([label1.title, label2.title])

        expect(whatsapp_channel).to receive(:send_template).exactly(3).times

        described_class.new(campaign: campaign).perform
      end

      it 'skips contacts without phone numbers' do
        contact_without_phone = create(:contact, account: account, phone_number: nil)
        contact_without_phone.update_labels([label1.title])

        expect(whatsapp_channel).not_to receive(:send_template)

        described_class.new(campaign: campaign).perform
      end

      it 'uses template processor service to process templates' do
        contact = create(:contact, :with_phone_number, account: account)
        contact.update_labels([label1.title])

        expect(Whatsapp::TemplateProcessorService).to receive(:new)
          .with(channel: whatsapp_channel, template_params: template_params)
          .and_call_original

        described_class.new(campaign: campaign).perform
      end

      it 'sends template message with correct parameters' do
        contact = create(:contact, :with_phone_number, account: account)
        contact.update_labels([label1.title])

        expect(whatsapp_channel).to receive(:send_template).with(
          contact.phone_number,
          hash_including(
            name: 'ticket_status_updated',
            namespace: '23423423_2342423_324234234_2343224',
            lang_code: 'en',
            parameters: array_including(
              hash_including(
                type: 'body',
                parameters: array_including(
                  hash_including(type: 'text', parameter_name: 'name', text: 'John'),
                  hash_including(type: 'text', parameter_name: 'ticket_id', text: '2332')
                )
              )
            )
          ),
          nil
        )

        described_class.new(campaign: campaign).perform
      end

      it 'processes liquid variables in template parameters' do
        contact = create(:contact, :with_phone_number, account: account, name: 'Jane Smith', email: 'jane@example.com')
        contact.update_labels([label1.title])

        campaign_with_liquid = create(:campaign, inbox: whatsapp_inbox, account: account,
                                                 audience: [{ type: 'Label', id: label1.id }],
                                                 template_params: {
                                                   'name' => 'ticket_status_updated',
                                                   'namespace' => '23423423_2342423_324234234_2343224',
                                                   'category' => 'UTILITY',
                                                   'language' => 'en',
                                                   'processed_params' => {
                                                     'body' => {
                                                       'name' => '{{contact.name}}',
                                                       'ticket_id' => '{{contact.email}}'
                                                     }
                                                   }
                                                 })

        contact_drop_name = ContactDrop.new(contact).name

        expect(whatsapp_channel).to receive(:send_template).with(
          contact.phone_number,
          hash_including(
            name: 'ticket_status_updated',
            namespace: '23423423_2342423_324234234_2343224',
            lang_code: 'en',
            parameters: array_including(
              hash_including(
                type: 'body',
                parameters: array_including(
                  hash_including(type: 'text', parameter_name: 'name', text: contact_drop_name),
                  hash_including(type: 'text', parameter_name: 'ticket_id', text: contact.email)
                )
              )
            )
          ),
          nil
        )

        described_class.new(campaign: campaign_with_liquid).perform
      end

      it 'skips contacts when liquid variables resolve to blank values' do
        contact = create(:contact, :with_phone_number, account: account, name: 'Jane', email: nil)
        contact.update_labels([label1.title])

        campaign_with_blank_liquid = create(:campaign, inbox: whatsapp_inbox, account: account,
                                                       audience: [{ type: 'Label', id: label1.id }],
                                                       template_params: {
                                                         'name' => 'test_template',
                                                         'namespace' => 'test_namespace',
                                                         'language' => 'en',
                                                         'processed_params' => {
                                                           'body' => {
                                                             'email' => '{{contact.email}}'
                                                           }
                                                         }
                                                       })

        expect(whatsapp_channel).not_to receive(:send_template)
        expect(Rails.logger).to receive(:info).with("Skipping contact #{contact.name} - liquid variables resolved to blank values")
        allow(Rails.logger).to receive(:info)

        described_class.new(campaign: campaign_with_blank_liquid).perform
      end
    end

    context 'when template_params is missing' do
      let(:template_params) { nil }

      it 'skips contacts and logs error' do
        contact = create(:contact, :with_phone_number, account: account)
        contact.update_labels([label1.title])

        expect(Rails.logger).to receive(:error)
          .with("Skipping contact #{contact.name} - no template_params found for WhatsApp campaign")
        expect(whatsapp_channel).not_to receive(:send_template)

        described_class.new(campaign: campaign).perform
      end
    end

    context 'when send_template raises an error' do
      it 'logs error and continues processing remaining contacts' do
        contact_error, contact_success = create_list(:contact, 2, :with_phone_number, account: account)
        contact_error.update_labels([label1.title])
        contact_success.update_labels([label1.title])
        error_message = 'WhatsApp API error'

        allow(whatsapp_channel).to receive(:send_template).and_return(nil)

        expect(whatsapp_channel).to receive(:send_template).with(contact_error.phone_number, anything, nil).and_raise(StandardError, error_message)
        expect(whatsapp_channel).to receive(:send_template).with(contact_success.phone_number, anything, nil).once

        expect(Rails.logger).to receive(:error)
          .with("Failed to send WhatsApp template message to #{contact_error.phone_number}: #{error_message}")
        expect(Rails.logger).to receive(:error).with(/Backtrace:/)

        described_class.new(campaign: campaign).perform
        expect(campaign.reload.completed?).to be true
      end
    end

    context 'when contacts already have a delivery for this campaign (e.g. reactivating a paused campaign)' do
      it 'does not resend to labeled contacts that already have a recorded send' do
        already_sent_contact, pending_contact = create_list(:contact, 2, :with_phone_number, account: account)
        already_sent_contact.update_labels([label1.title])
        pending_contact.update_labels([label1.title])
        CampaignMessageDelivery.create!(
          account: account, campaign: campaign, audience_type: 'labels', contact: already_sent_contact,
          phone_number: already_sent_contact.phone_number, source_id: 'wamid.already-sent'
        )

        described_class.new(campaign: campaign).perform

        enqueued_args = enqueued_jobs.select { |j| j[:job] == Campaigns::SendCampaignContactJob }.map { |j| j[:args] }
        expect(enqueued_args).to include([campaign.id, pending_contact.id])
        expect(enqueued_args).not_to include([campaign.id, already_sent_contact.id])
      end

      it 'does resend to a contact whose previous attempt never actually went out' do
        failed_contact = create(:contact, :with_phone_number, account: account)
        failed_contact.update_labels([label1.title])
        CampaignMessageDelivery.create!(
          account: account, campaign: campaign, audience_type: 'labels', contact: failed_contact,
          phone_number: failed_contact.phone_number, source_id: nil, status: 'failed'
        )

        described_class.new(campaign: campaign).perform

        enqueued_args = enqueued_jobs.select { |j| j[:job] == Campaigns::SendCampaignContactJob }.map { |j| j[:args] }
        expect(enqueued_args).to include([campaign.id, failed_contact.id])
      end

      it 'does not resend to a CSV phone number that already has a recorded send' do
        csv_campaign = create(:campaign, inbox: whatsapp_inbox, account: account, audience_type: 'csv', template_params: template_params)
        csv_campaign.csv_audience.attach(generate_csv_file([%w[phone_number name], ['+15550001111', 'Already Sent'], ['+15550002222', 'Pending']]))
        CampaignMessageDelivery.create!(
          account: account, campaign: csv_campaign, audience_type: 'csv',
          phone_number: '+15550001111', source_id: 'wamid.already-sent'
        )

        described_class.new(campaign: csv_campaign).perform

        enqueued_phones = enqueued_jobs
                          .select { |j| j[:job] == Campaigns::SendCampaignContactJob }
                          .map { |j| j[:args][2]['phone_number'] }
        expect(enqueued_phones).to include('+15550002222')
        expect(enqueued_phones).not_to include('+15550001111')
      end
    end

    context 'when the campaign has a configured timezone (regression for the UTC send-window bug)' do
      it 'schedules for today when the send window is still open in the campaign timezone, even at the UTC window boundary' do
        contact = create(:contact, :with_phone_number, account: account)
        contact.update_labels([label1.title])
        campaign.update!(timezone: 'America/Mexico_City', send_window_start: '09:00', send_window_end: '20:00')

        # 20:00 UTC is exactly the send_window_end when misread as UTC (the incident), but
        # it's only 14:00 in America/Mexico_City (UTC-6) - well inside the window. Before the
        # fix, advance_to_window compared against Time.current in the server's UTC zone and
        # pushed every contact to the next day.
        travel_to Time.utc(2026, 8, 14, 20, 0, 15) do
          described_class.new(campaign: campaign).perform
        end

        job = enqueued_jobs.find { |j| j[:job] == Campaigns::SendCampaignContactJob }
        expect(job).to be_present
        expect(Time.zone.at(job[:at]).to_date).to eq Date.new(2026, 8, 14)
      end

      it 'pushes to the next day when the send window has actually closed in the campaign timezone' do
        contact = create(:contact, :with_phone_number, account: account)
        contact.update_labels([label1.title])
        campaign.update!(timezone: 'America/Mexico_City', send_window_start: '09:00', send_window_end: '20:00')

        # 02:00:15 UTC on the 15th is 20:00:15 the previous day in America/Mexico_City -
        # genuinely past the window in the campaign's own timezone.
        travel_to Time.utc(2026, 8, 15, 2, 0, 15) do
          described_class.new(campaign: campaign).perform
        end

        job = enqueued_jobs.find { |j| j[:job] == Campaigns::SendCampaignContactJob }
        expect(job).to be_present
        expect(Time.zone.at(job[:at]).in_time_zone('America/Mexico_City').to_date).to eq Date.new(2026, 8, 15)
      end
    end
  end
end
