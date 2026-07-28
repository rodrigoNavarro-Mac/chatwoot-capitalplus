require 'rails_helper'

describe Cadences::ColdReactivationJob do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, phone_number: '+15551234567') }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, assignee: agent, status: 'open')
  end
  let(:cadence_definition) { create_cadence_definition!(whatsapp_inbox) }

  def build_enrollment(status:, snapshot_count:)
    CadenceEnrollment.create!(
      account: account, conversation: conversation, contact: contact, inbox: whatsapp_inbox,
      cadence_definition: cadence_definition, assignee_id: agent.id,
      status: status, current_step: snapshot_count, next_action_at: 1.day.ago,
      stopped_reason: status == :cold ? 'no_response_after_cadence' : nil,
      steps_snapshot: cadence_steps_snapshot(count: snapshot_count)
    )
  end

  before { account.enable_features!(:whatsapp_cadences) }

  it 'reactivates a cold enrollment whose cadence gained a step since it went cold' do
    # cadence_definition tiene 3 pasos (default_cadence_steps); el enrollment se congeló con 2
    enrollment = build_enrollment(status: :cold, snapshot_count: 2)

    expect { described_class.new.perform }
      .to have_enqueued_job(Cadences::AdvanceJob).with(enrollment.id)

    enrollment.reload
    expect(enrollment.status).to eq('active')
    expect(enrollment.stopped_reason).to be_nil
    expect(enrollment.total_steps).to eq(3)
    expect(enrollment.cadence_events.pluck(:event_type)).to include('cadence_resumed')
  end

  it 'does not touch a cold enrollment whose cadence did not grow' do
    build_enrollment(status: :cold, snapshot_count: 3)

    expect { described_class.new.perform }.not_to have_enqueued_job(Cadences::AdvanceJob)
  end

  it 'does not touch enrollments that are not cold' do
    enrollment = build_enrollment(status: :failed, snapshot_count: 2)

    expect { described_class.new.perform }.not_to have_enqueued_job(Cadences::AdvanceJob)
    expect(enrollment.reload.status).to eq('failed')
  end
end
