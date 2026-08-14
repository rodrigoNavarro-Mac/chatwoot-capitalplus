require 'rails_helper'

RSpec.describe Internal::RemoveOldWhatsappWebhookEventsJob do
  describe '#perform' do
    it 'removes events older than the retention period' do
      old_event = WhatsappWebhookEvent.create!(payload: { a: 1 }, created_at: 31.days.ago)
      recent_event = WhatsappWebhookEvent.create!(payload: { a: 1 }, created_at: 1.day.ago)

      described_class.perform_now

      expect(WhatsappWebhookEvent.exists?(old_event.id)).to be false
      expect(WhatsappWebhookEvent.exists?(recent_event.id)).to be true
    end
  end
end
