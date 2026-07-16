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
  end
end
