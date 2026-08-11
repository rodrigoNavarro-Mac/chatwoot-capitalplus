class Webhooks::AircallEventsJob < ApplicationJob
  queue_as :low

  def perform(account_id, params)
    account = Account.find_by(id: account_id)
    return if account.blank?

    Crm::Aircall::InboundWebhookService.new(account, params).perform
  rescue StandardError => e
    Rails.logger.error("[AIRCALL] AircallEventsJob failed for account ##{account_id}: #{e.message}")
  end
end
