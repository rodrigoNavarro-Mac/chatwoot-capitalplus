class Webhooks::ZohoCrmEventsJob < ApplicationJob
  queue_as :low

  def perform(account_id, params)
    account = Account.find_by(id: account_id)
    return if account.blank?

    Crm::Zoho::InboundWebhookService.new(account, params).perform
  rescue StandardError => e
    Rails.logger.error("[ZOHO CRM] ZohoCrmEventsJob failed for account ##{account_id}: #{e.message}")
  end
end
