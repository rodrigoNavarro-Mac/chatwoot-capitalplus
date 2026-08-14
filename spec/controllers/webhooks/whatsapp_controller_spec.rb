require 'rails_helper'

RSpec.describe 'Webhooks::WhatsappController', type: :request do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:client_secret) { 'test-whatsapp-secret' }
  let(:body) { { content: 'hello' }.to_json }

  def signature_for(body, secret = client_secret)
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
  end

  def post_whatsapp_webhook(path, body, signature: signature_for(body), env: { WHATSAPP_APP_SECRET: client_secret })
    with_modified_env env do
      post path,
           params: body,
           headers: { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => signature }
    end
  end

  def post_unsigned_whatsapp_webhook(path, body, env: { WHATSAPP_APP_SECRET: client_secret })
    with_modified_env env do
      post path,
           params: body,
           headers: { 'CONTENT_TYPE' => 'application/json' }
    end
  end

  before do
    InstallationConfig.where(name: 'WHATSAPP_APP_SECRET').delete_all
    GlobalConfig.clear_cache
  end

  describe 'GET /webhooks/verify' do
    it 'returns 401 when valid params are not present' do
      get "/webhooks/whatsapp/#{channel.phone_number}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 when invalid params' do
      get "/webhooks/whatsapp/#{channel.phone_number}",
          params: { 'hub.challenge' => '123456', 'hub.mode' => 'subscribe', 'hub.verify_token' => 'invalid' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns challenge when valid params' do
      get "/webhooks/whatsapp/#{channel.phone_number}",
          params: { 'hub.challenge' => '123456', 'hub.mode' => 'subscribe', 'hub.verify_token' => channel.provider_config['webhook_verify_token'] }
      expect(response.body).to include '123456'
    end
  end

  describe 'POST /webhooks/whatsapp/{:phone_number}' do
    it 'calls the whatsapp events job with the params for a valid signature' do
      allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)
      expect(Webhooks::WhatsappEventsJob).to receive(:perform_later)
      post_whatsapp_webhook('/webhooks/whatsapp/123221321', body)
      expect(response).to have_http_status(:success)
    end

    it 'accepts webhook payloads signed with the channel app secret' do
      channel_secret = 'channel-whatsapp-secret'
      channel.provider_config = channel.provider_config.merge('app_secret' => channel_secret)
      channel.save!

      allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)
      expect(Webhooks::WhatsappEventsJob).to receive(:perform_later)

      channel_body = {
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: {
              metadata: {
                display_phone_number: channel.phone_number.delete_prefix('+'),
                phone_number_id: channel.provider_config['phone_number_id']
              }
            }
          }]
        }]
      }.to_json

      post_whatsapp_webhook(
        "/webhooks/whatsapp/#{channel.phone_number}",
        channel_body,
        signature: signature_for(channel_body, channel_secret),
        env: {}
      )

      expect(response).to have_http_status(:success)
    end

    it 'accepts webhook payloads even when Meta sends display_phone_number with the Mexican mobile "1" prefix the channel does not have' do
      channel_secret = 'channel-whatsapp-secret'
      channel.update!(phone_number: '+525569440704', provider_config: channel.provider_config.merge('app_secret' => channel_secret))

      allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)
      expect(Webhooks::WhatsappEventsJob).to receive(:perform_later)

      channel_body = {
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: {
              metadata: {
                display_phone_number: '5215569440704',
                phone_number_id: channel.provider_config['phone_number_id']
              }
            }
          }]
        }]
      }.to_json

      post_whatsapp_webhook(
        "/webhooks/whatsapp/#{channel.phone_number}",
        channel_body,
        signature: signature_for(channel_body, channel_secret),
        env: {}
      )

      expect(response).to have_http_status(:success)
    end

    it 'skips signature validation for 360dialog channels' do
      dialog_channel = create(:channel_whatsapp, provider: 'default', sync_templates: false, validate_provider_config: false)
      allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)
      expect(Webhooks::WhatsappEventsJob).to receive(:perform_later)

      post_unsigned_whatsapp_webhook("/webhooks/whatsapp/#{dialog_channel.phone_number}", body)

      expect(response).to have_http_status(:success)
    end

    it 'skips signature validation for manual whatsapp cloud channels without an app secret' do
      channel.update!(
        provider_config: channel.provider_config.except('app_secret', 'app_secret_key', 'api_secret', 'client_secret', 'source')
      )
      allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)
      expect(Webhooks::WhatsappEventsJob).to receive(:perform_later)

      channel_body = {
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: {
              metadata: {
                display_phone_number: channel.phone_number.delete_prefix('+'),
                phone_number_id: channel.provider_config['phone_number_id']
              }
            }
          }]
        }]
      }.to_json

      post_unsigned_whatsapp_webhook("/webhooks/whatsapp/#{channel.phone_number}", channel_body)

      expect(response).to have_http_status(:success)
    end

    it 'returns unauthorized when signature is missing' do
      allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)

      with_modified_env WHATSAPP_APP_SECRET: client_secret do
        post '/webhooks/whatsapp/123221321',
             params: body,
             headers: { 'CONTENT_TYPE' => 'application/json' }
      end

      expect(response).to have_http_status(:unauthorized)
      expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
    end

    it 'returns unauthorized when signature is invalid' do
      allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)

      post_whatsapp_webhook('/webhooks/whatsapp/123221321', body, signature: 'sha256=invalid-signature')

      expect(response).to have_http_status(:unauthorized)
      expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
    end

    it 'persists the raw payload even when the webhook is rejected for an invalid signature' do
      expect do
        post_whatsapp_webhook('/webhooks/whatsapp/123221321', body, signature: 'sha256=invalid-signature')
      end.to change(WhatsappWebhookEvent, :count).by(1)

      expect(response).to have_http_status(:unauthorized)
      expect(WhatsappWebhookEvent.last.payload['content']).to eq('hello')
    end

    it 'persists the raw payload for a successfully processed webhook' do
      allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)

      channel_body = {
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: {
              metadata: {
                display_phone_number: channel.phone_number.delete_prefix('+'),
                phone_number_id: channel.provider_config['phone_number_id']
              }
            }
          }]
        }]
      }.to_json

      expect do
        post_whatsapp_webhook(
          "/webhooks/whatsapp/#{channel.phone_number}",
          channel_body,
          signature: signature_for(channel_body, client_secret),
          env: {}
        )
      end.to change(WhatsappWebhookEvent, :count).by(1)

      event = WhatsappWebhookEvent.last
      expect(event.phone_number_id).to eq(channel.provider_config['phone_number_id'])
      expect(event.phone_number).to eq(channel.phone_number)
    end

    context 'when phone number is in inactive list' do
      before do
        allow(GlobalConfig).to receive(:get_value).with('INACTIVE_WHATSAPP_NUMBERS').and_return('+1234567890,+9876543210')
      end

      it 'returns service unavailable for inactive phone number in URL params' do
        allow(Rails.logger).to receive(:warn)
        expect(Rails.logger).to receive(:warn).with('Rejected webhook for inactive WhatsApp number: +1234567890')

        post_whatsapp_webhook('/webhooks/whatsapp/+1234567890', body)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Inactive WhatsApp number')
      end
    end

    context 'when INACTIVE_WHATSAPP_NUMBERS config is not set' do
      before do
        allow(GlobalConfig).to receive(:get_value).with('INACTIVE_WHATSAPP_NUMBERS').and_return(nil)
      end

      it 'processes the webhook normally' do
        allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)
        expect(Webhooks::WhatsappEventsJob).to receive(:perform_later)

        post_whatsapp_webhook('/webhooks/whatsapp/+1234567890', body)
        expect(response).to have_http_status(:success)
      end
    end
  end
end
