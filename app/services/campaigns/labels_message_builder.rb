# Resolves (or creates) the conversation for an existing labels-audience contact and
# builds a real outgoing Message for it, so the campaign send gains delivery/response
# tracking for free via the same source_id correlation used for 1:1 messages.
class Campaigns::LabelsMessageBuilder
  pattr_initialize [:campaign!]

  delegate :inbox, to: :campaign

  def build(contact)
    contact_inbox = find_or_create_contact_inbox(contact)
    return if contact_inbox.nil?

    conversation = find_or_create_conversation(contact_inbox)

    Messages::MessageBuilder.new(
      campaign.sender,
      conversation,
      ActionController::Parameters.new(content: campaign.message, campaign_id: campaign.id)
    ).perform
  rescue StandardError => e
    Rails.logger.error "Failed to build campaign message for contact #{contact.id}: #{e.message}"
    nil
  end

  private

  def find_or_create_contact_inbox(contact)
    contact.contact_inboxes.find_by(inbox_id: inbox.id) ||
      ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
  end

  def find_or_create_conversation(contact_inbox)
    contact_inbox.conversations.last || Conversation.create!(
      account_id: campaign.account_id,
      inbox_id: contact_inbox.inbox_id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id
    )
  end
end
