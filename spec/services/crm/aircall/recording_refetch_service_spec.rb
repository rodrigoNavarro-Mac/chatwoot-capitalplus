require 'rails_helper'

describe Crm::Aircall::RecordingRefetchService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:call) { create(:call, account: account, conversation: conversation, provider: :aircall, provider_call_id: '999') }
  let(:recording_url) { 'https://production-fra-example.s3.eu-central-1.amazonaws.com/recording.mp3?X-Amz-Signature=abc123' }

  def stub_show(recording: recording_url)
    stub_request(:get, 'https://api.aircall.io/v1/calls/999')
      .to_return(status: 200, body: { call: { 'id' => 999, 'recording' => recording } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  context 'without an Aircall hook configured' do
    it 'returns false and makes no HTTP request' do
      expect(Crm::Aircall::Api::CallsClient).not_to receive(:new)

      expect(described_class.new(call: call).perform).to be(false)
      expect(call.reload.recording).not_to be_attached
    end
  end

  context 'with an Aircall hook configured' do
    before do
      create(:integrations_hook, account: account, app_id: 'aircall', status: 'enabled',
                                 settings: { webhook_secret: 'x', api_id: 'my-api-id', api_token: 'my-api-token' })
    end

    it 're-fetches the recording URL from GET /v1/calls/:id and attaches it' do
      stub_show
      stub_request(:get, recording_url).to_return(status: 200, body: 'FAKE_AUDIO_BYTES', headers: { 'Content-Type' => 'audio/mpeg' })

      expect(described_class.new(call: call).perform).to be(true)
      expect(call.reload.recording).to be_attached
    end

    it 'returns false when Aircall has no recording URL for this call' do
      stub_show(recording: nil)

      expect(described_class.new(call: call).perform).to be(false)
      expect(call.reload.recording).not_to be_attached
    end

    it 'returns true without any HTTP request when a recording is already attached' do
      call.recording.attach(io: StringIO.new('existing'), filename: 'existing.wav', content_type: 'audio/wav')

      expect(Crm::Aircall::Api::CallsClient).not_to receive(:new)

      expect(described_class.new(call: call).perform).to be(true)
    end

    it 'returns false and tracks the exception when the Aircall API errors out' do
      stub_request(:get, 'https://api.aircall.io/v1/calls/999').to_return(status: 500, body: 'boom')
      expect(ChatwootExceptionTracker).to receive(:new).and_call_original

      expect(described_class.new(call: call).perform).to be(false)
      expect(call.reload.recording).not_to be_attached
    end
  end
end
