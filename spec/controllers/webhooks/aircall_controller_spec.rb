require 'rails_helper'

RSpec.describe 'Webhooks::AircallController', type: :request do
  let(:account) { create(:account) }
  let(:secret) { 'test-secret-token' }

  def post_webhook(secret_token, payload, account_id: account.id)
    post "/webhooks/aircall/#{account_id}/#{secret_token}", params: payload, as: :json
  end

  it 'returns not_found for an unknown account' do
    post_webhook(secret, { event: 'call.ended' }, account_id: 0)

    expect(response).to have_http_status(:not_found)
  end

  context 'without a configured aircall hook' do
    it 'returns unauthorized' do
      post_webhook(secret, { event: 'call.ended', data: {} })

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'with a configured aircall hook' do
    before do
      create(:integrations_hook, account: account, app_id: 'aircall', status: 'enabled', settings: { webhook_secret: secret })
    end

    it 'returns unauthorized when the secret in the URL does not match' do
      post_webhook('wrong-secret', { event: 'call.ended', data: {} })

      expect(response).to have_http_status(:unauthorized)
    end

    it 'enqueues the events job and returns ok when the secret matches' do
      expect do
        post_webhook(secret, { event: 'call.ended', data: { id: 123 } })
      end.to have_enqueued_job(Webhooks::AircallEventsJob).with(account.id, hash_including('event' => 'call.ended'))

      expect(response).to have_http_status(:ok)
    end
  end
end
