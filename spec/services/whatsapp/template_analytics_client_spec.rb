require 'rails_helper'

describe Whatsapp::TemplateAnalyticsClient do
  let(:client) { described_class.new(waba_id: 'waba-123', access_token: 'token-123') }
  let(:start_time) { Time.zone.parse('2026-08-01') }
  let(:end_time) { Time.zone.parse('2026-08-08') }

  describe '#fetch' do
    it 'raises when no template_ids are given' do
      expect { client.fetch(template_ids: [], start_time: start_time, end_time: end_time) }
        .to raise_error(ArgumentError, /must not be empty/)
    end

    it 'raises when more than 10 template_ids are given' do
      expect { client.fetch(template_ids: (1..11).to_a, start_time: start_time, end_time: end_time) }
        .to raise_error(ArgumentError, /maximum of 10/)
    end

    it 'sums data points per template and returns a hash keyed by template_id' do
      stub_request(:get, 'https://graph.facebook.com/v22.0/waba-123')
        .with(query: hash_including('access_token' => 'token-123'))
        .to_return(
          status: 200,
          body: {
            template_analytics: {
              data: [
                {
                  data_points: [
                    { template_id: '111', sent: 10, delivered: 9, read: 5, clicked: [{ count: 2 }] },
                    { template_id: '111', sent: 5, delivered: 5, read: 3, clicked: [] }
                  ]
                }
              ]
            }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.fetch(template_ids: ['111'], start_time: start_time, end_time: end_time)

      expect(result['111']).to eq(sent: 15, delivered: 14, read: 8, clicked: 2)
    end

    it 'raises when the HTTP request fails' do
      stub_request(:get, 'https://graph.facebook.com/v22.0/waba-123')
        .with(query: hash_including('access_token' => 'token-123'))
        .to_return(status: 400, body: { error: { message: 'bad request' } }.to_json)

      expect { client.fetch(template_ids: ['111'], start_time: start_time, end_time: end_time) }
        .to raise_error(/Meta template_analytics request failed/)
    end

    it 'raises when the response shape is unrecognized' do
      stub_request(:get, 'https://graph.facebook.com/v22.0/waba-123')
        .with(query: hash_including('access_token' => 'token-123'))
        .to_return(status: 200, body: { unexpected: true }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect { client.fetch(template_ids: ['111'], start_time: start_time, end_time: end_time) }
        .to raise_error(/Unexpected template_analytics response shape/)
    end
  end
end
