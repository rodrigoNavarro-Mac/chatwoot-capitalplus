require 'rails_helper'

describe Crm::Aircall::CallHistoryBackfillService do
  let(:account) { create(:account) }
  let(:client) { instance_double(Crm::Aircall::Api::CallsClient) }
  let(:august_start) { Time.zone.parse('2026-08-01T00:00:00Z') }
  let(:august_end) { august_start.end_of_month }
  let(:july_start) { Time.zone.parse('2026-07-01T00:00:00Z') }
  let(:july_end) { july_start.end_of_month }

  before do
    stub_const("#{described_class}::RATE_LIMIT_DELAY", 0)
    travel_to Time.zone.parse('2026-08-15T12:00:00Z')
    allow(Crm::Aircall::Api::CallsClient).to receive(:new).and_return(client)
  end

  context 'when there is no enabled aircall hook' do
    it 'does nothing and never instantiates the api client' do
      described_class.new(account).perform

      expect(Crm::Aircall::Api::CallsClient).not_to have_received(:new)
    end
  end

  context 'with an enabled aircall hook' do
    before do
      create(:integrations_hook, account: account, app_id: 'aircall', status: 'enabled',
                                 settings: { webhook_secret: 'x', api_id: 'id', api_token: 'token' })
    end

    it 'walks backward month by month and stops at the first month with no calls' do
      expect(client).to receive(:list).with(from: august_start, to: august_end, page: 1)
                                      .and_return({ 'calls' => [{ 'id' => 1 }], 'meta' => {} })
      expect(client).to receive(:list).with(from: july_start, to: july_end, page: 1)
                                      .and_return({ 'calls' => [], 'meta' => {} })
      processor = instance_double(Crm::Aircall::CallProcessor, perform: true)
      allow(Crm::Aircall::CallProcessor).to receive(:new).and_return(processor)

      described_class.new(account).perform

      expect(Crm::Aircall::CallProcessor).to have_received(:new).with(account: account, call_data: { 'id' => 1 })
    end

    it 'paginates within a month by following meta.next_page_link' do
      allow(client).to receive(:list).with(from: august_start, to: august_end, page: 1)
                                     .and_return({ 'calls' => [{ 'id' => 1 }], 'meta' => { 'next_page_link' => 'x' } })
      allow(client).to receive(:list).with(from: august_start, to: august_end, page: 2)
                                     .and_return({ 'calls' => [{ 'id' => 2 }], 'meta' => {} })
      allow(client).to receive(:list).with(from: july_start, to: july_end, page: 1)
                                     .and_return({ 'calls' => [], 'meta' => {} })
      processor = instance_double(Crm::Aircall::CallProcessor, perform: true)
      allow(Crm::Aircall::CallProcessor).to receive(:new).and_return(processor)

      described_class.new(account).perform

      expect(Crm::Aircall::CallProcessor).to have_received(:new).with(account: account, call_data: { 'id' => 1 })
      expect(Crm::Aircall::CallProcessor).to have_received(:new).with(account: account, call_data: { 'id' => 2 })
    end

    it 'logs and continues when processing an individual call fails' do
      allow(client).to receive(:list).with(from: august_start, to: august_end, page: 1)
                                     .and_return({ 'calls' => [{ 'id' => 1 }, { 'id' => 2 }], 'meta' => {} })
      allow(client).to receive(:list).with(from: july_start, to: july_end, page: 1)
                                     .and_return({ 'calls' => [], 'meta' => {} })
      failing_processor = instance_double(Crm::Aircall::CallProcessor)
      allow(failing_processor).to receive(:perform).and_raise(StandardError, 'boom')
      ok_processor = instance_double(Crm::Aircall::CallProcessor, perform: true)
      allow(Crm::Aircall::CallProcessor).to receive(:new).with(account: account, call_data: { 'id' => 1 }).and_return(failing_processor)
      allow(Crm::Aircall::CallProcessor).to receive(:new).with(account: account, call_data: { 'id' => 2 }).and_return(ok_processor)
      allow(Rails.logger).to receive(:error)

      described_class.new(account).perform

      expect(Rails.logger).to have_received(:error).with(/call_id=1.*boom/)
      expect(ok_processor).to have_received(:perform)
    end
  end
end
