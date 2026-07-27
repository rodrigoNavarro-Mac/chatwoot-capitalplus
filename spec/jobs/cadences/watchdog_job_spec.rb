require 'rails_helper'

describe Cadences::WatchdogJob do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, phone_number: '+15551234567') }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, assignee: agent, status: 'open')
  end
  let(:cadence_definition) { create_cadence_definition!(whatsapp_inbox) }

  def build_enrollment(status:, next_action_at:, current_step: 1)
    CadenceEnrollment.create!(
      account: account, conversation: conversation, contact: contact, inbox: whatsapp_inbox,
      cadence_definition: cadence_definition, assignee_id: agent.id,
      status: status, current_step: current_step, next_action_at: next_action_at,
      steps_snapshot: cadence_steps_snapshot(count: 3)
    )
  end

  before { account.enable_features!(:whatsapp_cadences) }

  it 'enqueues AdvanceJob for an overdue active enrollment' do
    enrollment = build_enrollment(status: :active, next_action_at: 20.minutes.ago)

    expect { described_class.new.perform }.to have_enqueued_job(Cadences::AdvanceJob).with(enrollment.id)
  end

  it 'enqueues CheckResponseJob (not AdvanceJob) for an overdue waiting_response enrollment' do
    enrollment = build_enrollment(status: :waiting_response, next_action_at: 20.minutes.ago, current_step: 2)

    expect { described_class.new.perform }
      .to have_enqueued_job(Cadences::CheckResponseJob).with(enrollment.id, enrollment.current_step)

    expect(Cadences::AdvanceJob).not_to have_been_enqueued
  end

  it 'does not retrigger an enrollment whose next_action_at is still within the stale threshold' do
    build_enrollment(status: :active, next_action_at: 5.minutes.ago)

    expect { described_class.new.perform }.not_to have_enqueued_job(Cadences::AdvanceJob)
  end

  it 'does not retrigger a failed enrollment even if next_action_at is overdue' do
    build_enrollment(status: :failed, next_action_at: 1.hour.ago)

    expect { described_class.new.perform }.not_to have_enqueued_job(Cadences::AdvanceJob)
  end

  it 'does not retrigger an enrollment with a nil next_action_at' do
    build_enrollment(status: :active, next_action_at: nil)

    expect { described_class.new.perform }.not_to have_enqueued_job(Cadences::AdvanceJob)
  end
end
