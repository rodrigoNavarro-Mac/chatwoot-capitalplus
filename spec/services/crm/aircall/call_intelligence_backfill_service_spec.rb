require 'rails_helper'

describe Crm::Aircall::CallIntelligenceBackfillService do
  subject(:service) { described_class.new(account: account, from: from, to: to) }

  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:from) { Time.zone.parse('2026-08-01') }
  let(:to) { Time.zone.parse('2026-08-31T23:59:59') }
  let!(:call_without_analysis) do
    create(:call, account: account, conversation: conversation, provider: :aircall, status: 'completed',
                  provider_call_id: '111', started_at: Time.zone.parse('2026-08-15'))
  end

  # `hook` habilita la API en #perform! sin usarse por nombre; los `call_*` de abajo solo existen
  # para probar que #pending_calls los EXCLUYE (ya analizada / fuera de rango / no completada) —
  # ninguno se referencia por nombre en los ejemplos, por eso let! en vez de let.
  # rubocop:disable RSpec/LetSetup
  let!(:hook) { create(:integrations_hook, account: account, app_id: 'aircall', status: 'enabled', settings: { api_id: 'id', api_token: 'token' }) }
  let!(:call_already_analyzed) do
    call = create(:call, account: account, conversation: conversation, provider: :aircall, status: 'completed',
                         provider_call_id: '222', started_at: Time.zone.parse('2026-08-10'))
    create(:call_analysis, call: call)
    call
  end
  let!(:call_outside_range) do
    create(:call, account: account, conversation: conversation, provider: :aircall, status: 'completed',
                  provider_call_id: '333', started_at: Time.zone.parse('2026-07-15'))
  end
  let!(:call_not_completed) do
    create(:call, account: account, conversation: conversation, provider: :aircall, status: 'no_answer',
                  provider_call_id: '444', started_at: Time.zone.parse('2026-08-20'))
  end
  # rubocop:enable RSpec/LetSetup

  describe '#pending_calls' do
    it 'only includes completed Aircall calls in range without an existing analysis' do
      expect(service.pending_calls).to contain_exactly(call_without_analysis)
    end
  end

  describe '#perform!' do
    before do
      stub_request(:get, %r{api\.aircall\.io/v1/calls})
        .to_return(status: 200, body: { calls: [{ id: 111, recording: 'https://example.com/rec.mp3' }], meta: {} }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'enqueues RecordingAndTranscriptJob only for pending calls, with the matching recording url' do
      expect { service.perform! }.to have_enqueued_job(Crm::Aircall::RecordingAndTranscriptJob)
        .with(call_without_analysis.id, recording_url: 'https://example.com/rec.mp3')
        .exactly(1).times
    end

    it 'returns the number of calls it queued' do
      expect(service.perform!).to eq(1)
    end
  end
end
