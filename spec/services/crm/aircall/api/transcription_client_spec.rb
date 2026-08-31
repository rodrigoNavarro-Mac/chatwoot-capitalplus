require 'rails_helper'

describe Crm::Aircall::Api::TranscriptionClient do
  let(:account) { create(:account) }
  let(:hook) do
    create(:integrations_hook, account: account, app_id: 'aircall', status: 'enabled',
                               settings: { webhook_secret: 'x', api_id: 'my-api-id', api_token: 'my-api-token' })
  end

  # Shape real confirmado contra la documentación oficial de Aircall (2026-08-31).
  let(:real_shape_body) do
    {
      transcription: {
        id: 68_271, call_id: 5_237_603, call_created_at: '2024-07-26T13:30:54.000Z', type: 'call',
        content: {
          language: 'en',
          utterances: [
            { start_time: 12.54, end_time: 13.8, text: 'Okay,', participant_type: 'external', phone_number: '+33679198915' },
            { start_time: 238.08, end_time: 239.48, text: "Okay, I guess that's enough.", participant_type: 'internal', user_id: 123 }
          ]
        }
      }
    }.to_json
  end

  describe '#fetch_segments' do
    it 'normalizes utterances from the real transcription.content.utterances shape' do
      stub_request(:get, %r{api\.aircall\.io/v1/calls/123/transcription})
        .to_return(status: 200, body: real_shape_body, headers: { 'Content-Type' => 'application/json' })

      segments = described_class.new(hook).fetch_segments('123')

      expect(segments).to eq([
                               { speaker: 'Cliente', role_hint: 'external', start_seconds: 13, end_seconds: 14, text: 'Okay,' },
                               { speaker: 'Agente', role_hint: 'agent', start_seconds: 238, end_seconds: 239, text: "Okay, I guess that's enough." }
                             ])
    end

    it 'authenticates with basic auth using the hook\'s api_id/api_token' do
      stub = stub_request(:get, %r{api\.aircall\.io/v1/calls/123/transcription})
             .with(basic_auth: %w[my-api-id my-api-token])
             .to_return(status: 200, body: real_shape_body, headers: { 'Content-Type' => 'application/json' })

      described_class.new(hook).fetch_segments('123')

      expect(stub).to have_been_requested
    end

    it 'returns an empty array when Aircall AI is still processing (202)' do
      stub_request(:get, %r{api\.aircall\.io/v1/calls/123/transcription}).to_return(status: 202, body: '')

      expect(described_class.new(hook).fetch_segments('123')).to eq([])
    end

    it 'returns an empty array when the transcription is not found yet (404)' do
      stub_request(:get, %r{api\.aircall\.io/v1/calls/123/transcription}).to_return(status: 404, body: '')

      expect(described_class.new(hook).fetch_segments('123')).to eq([])
    end

    it 'raises NotAvailableError when the account has no Aircall AI add-on (403)' do
      stub_request(:get, %r{api\.aircall\.io/v1/calls/123/transcription})
        .to_return(status: 403, body: { message: 'Forbidden' }.to_json)

      expect { described_class.new(hook).fetch_segments('123') }
        .to raise_error(described_class::NotAvailableError)
    end

    it 'raises ApiError on other error statuses' do
      stub_request(:get, %r{api\.aircall\.io/v1/calls/123/transcription}).to_return(status: 500, body: 'boom')

      expect { described_class.new(hook).fetch_segments('123') }
        .to raise_error(described_class::ApiError, /500/)
    end
  end
end
