require 'rails_helper'

describe Cadences::StepExecutor do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, phone_number: '+15551234567') }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, assignee: agent, status: 'open')
  end
  let(:enrollment) { Cadences::EnrollmentService.new(conversation: conversation).enroll! }
  let!(:cadence_definition) { create_cadence_steps!(whatsapp_inbox) }

  before do
    account.enable_features!(:whatsapp_cadences)
    stub_request(:post, /graph\.facebook\.com.*messages/)
      .to_return(status: 200, body: { messages: [{ id: 'wamid.step1' }] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#execute_current_step!' do
    it 'sends the step 1 template and schedules the response check' do
      expect { described_class.new(enrollment: enrollment).execute_current_step! }
        .to have_enqueued_job(Cadences::CheckResponseJob).with(enrollment.id, 1)

      enrollment.reload
      expect(enrollment.current_step).to eq(1)
      expect(enrollment.status).to eq('waiting_response')
      expect(enrollment.last_template_sent_at).to be_present
      expect(enrollment.cadence_events.pluck(:event_type)).to include('template_sent')
    end

    it 'persists the sent template as a visible outgoing message in the conversation' do
      described_class.new(enrollment: enrollment).execute_current_step!

      message = conversation.messages.outgoing.last
      expect(message).to be_present
      expect(message.source_id).to eq('wamid.step1')
      expect(message.status).to eq('sent')
      expect(message.additional_attributes.dig('template_params', 'name')).to be_present
      expect(message.additional_attributes['cadence_enrollment_id']).to eq(enrollment.id)
      expect(message.additional_attributes['cadence_step']).to eq(1)
    end

    it 'does not resend the step once already sent (idempotent)' do
      described_class.new(enrollment: enrollment).execute_current_step!
      enrollment.reload

      expect { described_class.new(enrollment: enrollment).execute_current_step! }
        .not_to(change { enrollment.reload.cadence_events.where(event_type: 'template_sent').count })
    end

    it 'does not send when the lead already responded since the last template' do
      enrollment.update!(status: :waiting_response, last_template_sent_at: 1.hour.ago, last_lead_response_at: Time.current)

      expect { described_class.new(enrollment: enrollment).execute_current_step! }
        .not_to have_enqueued_job(Cadences::CheckResponseJob)
    end

    it 'includes the configured media_url in the template header when present' do
      cadence_definition.cadence_step_definitions.find_by(position: 1)
                        .update!(media_url: 'https://cdn.example.com/video.mp4', media_type: 'video')
      enrollment # force creation with the updated step definition in its snapshot

      # No hace falta un template real registrado en el canal (find_template) para probar
      # esto: alcanza con verificar que StepExecutor arma el header con el media_url/type
      # configurado y se lo pasa a Whatsapp::TemplateProcessorService; el resto del pipeline
      # (resolución del template real de Meta) ya está cubierto por otros specs.
      expect(Whatsapp::TemplateProcessorService).to receive(:new).with(
        hash_including(
          template_params: hash_including(
            'processed_params' => hash_including(
              'header' => hash_including('media_url' => 'https://cdn.example.com/video.mp4', 'media_type' => 'video')
            )
          )
        )
      ).and_call_original

      described_class.new(enrollment: enrollment).execute_current_step!
    end

    it 'attaches the header media as a previewable Attachment on the message' do
      cadence_definition.cadence_step_definitions.find_by(position: 1)
                        .update!(media_url: 'https://cdn.example.com/video.mp4', media_type: 'video')
      enrollment # force creation with the updated step definition in its snapshot

      described_class.new(enrollment: enrollment).execute_current_step!

      attachment = conversation.messages.outgoing.last.attachments.last
      expect(attachment).to be_present
      expect(attachment.file_type).to eq('video')
      expect(attachment.external_url).to eq('https://cdn.example.com/video.mp4')
    end

    it 'persists the rendered template body as the message content, not the internal template name' do
      cadence_definition.cadence_step_definitions.find_by(position: 1)
                        .update!(body_variables: { '1' => 'Hola {{ contact.name }}' })
      new_template = {
        'name' => 'cadencia_paso_1',
        'language' => 'es_MX',
        'status' => 'approved',
        'components' => [{ 'type' => 'BODY', 'text' => '{{1}}, tenemos una oferta para ti.' }]
      }
      whatsapp_channel.update!(message_templates: whatsapp_channel.message_templates + [new_template])
      enrollment # force creation with the updated step definition and registered template

      described_class.new(enrollment: enrollment).execute_current_step!

      message = conversation.messages.outgoing.last
      expect(message.content).to eq("Hola #{contact.name}, tenemos una oferta para ti.")
    end

    it 'resolves body_variables through Liquid using the contact drop' do
      cadence_definition.cadence_step_definitions.find_by(position: 1)
                        .update!(body_variables: { '1' => 'Hola {{ contact.name }}' })
      enrollment # force creation with the updated step definition in its snapshot

      expect(Whatsapp::TemplateProcessorService).to receive(:new).with(
        hash_including(
          template_params: hash_including(
            'processed_params' => hash_including(
              'body' => { '1' => "Hola #{contact.name}" }
            )
          )
        )
      ).and_call_original

      described_class.new(enrollment: enrollment).execute_current_step!
    end

    it 'terminates the cadence when the conversation is no longer eligible' do
      enrollment # force creation while the conversation is still open
      conversation.update!(status: :resolved)

      described_class.new(enrollment: enrollment).execute_current_step!

      expect(enrollment.reload.status).to eq('failed')
      expect(enrollment.stopped_reason).to eq('ineligible')
    end

    it 'persists the real WhatsApp API error message when the send fails' do
      enrollment # force creation before overriding the stub
      stub_request(:post, /graph\.facebook\.com.*messages/)
        .to_return(status: 400, body: { error: { message: 'Template name does not exist in the translation' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      described_class.new(enrollment: enrollment).execute_current_step!

      expect(enrollment.reload.status).to eq('failed')
      expect(enrollment.stopped_reason).to eq('send_failed: Template name does not exist in the translation')
    end

    it 'retries instead of failing when Meta returns a media upload error (transient)' do
      enrollment # force creation before overriding the stub
      stub_request(:post, /graph\.facebook\.com.*messages/)
        .to_return(status: 400, body: { error: { message: 'Media upload error', code: 131_053 } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect { described_class.new(enrollment: enrollment).execute_current_step! }
        .to have_enqueued_job(Cadences::AdvanceJob).with(enrollment.id)

      enrollment.reload
      expect(enrollment.status).to eq('active')
      expect(enrollment.send_retry_count).to eq(1)
      expect(enrollment.next_action_at).to be_within(5.seconds).of(2.minutes.from_now)
    end

    it 'fails immediately without retrying when the media_url is a Google Drive share link (permanently broken, not transient)' do
      cadence_definition.cadence_step_definitions.find_by(position: 1)
                        .update!(media_url: 'https://drive.google.com/file/d/abc123/view?usp=sharing', media_type: 'video')
      enrollment # force creation with the updated step definition in its snapshot

      expect { described_class.new(enrollment: enrollment).execute_current_step! }
        .not_to have_enqueued_job(Cadences::AdvanceJob)

      enrollment.reload
      expect(enrollment.status).to eq('failed')
      expect(enrollment.stopped_reason).to include('invalid_media_url')
      expect(enrollment.send_retry_count).to eq(0)
    end

    it 'does not flag an object-storage media_url without a file extension as invalid (it can still resolve a valid Content-Type)' do
      cadence_definition.cadence_step_definitions.find_by(position: 1)
                        .update!(media_url: 'https://cdn.example.com/blob/imagen-sin-extension', media_type: 'image')
      enrollment # force creation with the updated step definition in its snapshot

      expect { described_class.new(enrollment: enrollment).execute_current_step! }
        .to have_enqueued_job(Cadences::CheckResponseJob)

      expect(enrollment.reload.status).to eq('waiting_response')
    end

    it 'retries when the HTTP call itself times out (network-level transient failure)' do
      enrollment # force creation before overriding the stub
      stub_request(:post, /graph\.facebook\.com.*messages/).to_timeout

      described_class.new(enrollment: enrollment).execute_current_step!

      enrollment.reload
      expect(enrollment.status).to eq('active')
      expect(enrollment.send_retry_count).to eq(1)
    end

    it 'resets send_retry_count once a step finally sends successfully' do
      enrollment.update!(send_retry_count: 3)

      described_class.new(enrollment: enrollment).execute_current_step!

      expect(enrollment.reload.send_retry_count).to eq(0)
    end

    it 'does not reset send_retry_count when a media step is merely accepted by Meta, since it can still fail validation asynchronously' do
      cadence_definition.cadence_step_definitions.find_by(position: 1)
                        .update!(media_url: 'https://cdn.example.com/video.mp4', media_type: 'video')
      enrollment # force creation with the updated step definition in its snapshot
      enrollment.update!(send_retry_count: 1)

      described_class.new(enrollment: enrollment).execute_current_step!

      expect(enrollment.reload.send_retry_count).to eq(1)
    end

    it 'reschedules instead of sending when another send already claimed the rate limit slot for this inbox' do
      enrollment # force creation
      rate_limiter = instance_double(Cadences::SendRateLimiter, claim_slot!: false)
      allow(Cadences::SendRateLimiter).to receive(:new).with(inbox: whatsapp_inbox).and_return(rate_limiter)

      expect { described_class.new(enrollment: enrollment).execute_current_step! }
        .to have_enqueued_job(Cadences::AdvanceJob).with(enrollment.id)

      enrollment.reload
      expect(enrollment.status).to eq('active')
      expect(enrollment.current_step).to eq(0)
    end

    it 'does not reschedule the same enrollment twice for the same inbox within the rate limit window' do
      other_contact = create(:contact, account: account, phone_number: '+15559998888')
      other_conversation = create(:conversation, account: account, inbox: whatsapp_inbox, contact: other_contact, assignee: agent, status: 'open')
      other_enrollment = Cadences::EnrollmentService.new(conversation: other_conversation).enroll!

      described_class.new(enrollment: enrollment).execute_current_step!
      expect(enrollment.reload.status).to eq('waiting_response')

      expect { described_class.new(enrollment: other_enrollment).execute_current_step! }
        .to have_enqueued_job(Cadences::AdvanceJob).with(other_enrollment.id)

      expect(other_enrollment.reload.status).to eq('active')
    end
  end
end
