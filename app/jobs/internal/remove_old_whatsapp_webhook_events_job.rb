# housekeeping
# removes raw WhatsApp webhook audit rows older than the retention window, so
# the table (see WhatsappWebhookEvent) doesn't grow unbounded

class Internal::RemoveOldWhatsappWebhookEventsJob < ApplicationJob
  queue_as :purgable

  RETENTION_PERIOD = 30.days

  def perform
    WhatsappWebhookEvent.where('created_at < ?', RETENTION_PERIOD.ago).delete_all
  end
end
