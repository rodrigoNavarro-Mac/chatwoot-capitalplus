class Contacts::FilterService < FilterService
  ATTRIBUTE_MODEL = 'contact_attribute'.freeze

  # Engagement filters (attribute_type "engagement" in filter_keys.yml) have no column of their own:
  # each one is a correlated subquery against the contact row, used to build WhatsApp campaign segments
  # such as "never replied" or "hasn't replied in 30 days".
  ENGAGEMENT_EXPRESSIONS = {
    # Last message the contact sent us
    'last_replied_at' => <<~SQL.squish,
      SELECT MAX(engagement_messages.created_at) FROM messages engagement_messages
      WHERE engagement_messages.sender_type = 'Contact' AND engagement_messages.sender_id = contacts.id
        AND engagement_messages.message_type = 0
    SQL
    # Last outgoing message (agent, bot or WhatsApp template/campaign) we sent the contact. Excludes
    # message_type 3 ("template"), which is the inbox's automatic greeting/out-of-office reply.
    'last_message_sent_at' => <<~SQL.squish,
      SELECT MAX(engagement_messages.created_at) FROM messages engagement_messages
      INNER JOIN conversations engagement_conversations ON engagement_conversations.id = engagement_messages.conversation_id
      WHERE engagement_conversations.contact_id = contacts.id
        AND engagement_messages.message_type = 1 AND engagement_messages.private = false
    SQL
    # Last WhatsApp campaign message that reached Meta; CSV deliveries have no contact_id, so they
    # are matched by the last 10 digits of the phone (covers the Mexican 52/521 variants)
    'last_campaign_sent_at' => <<~SQL.squish
      SELECT MAX(engagement_deliveries.sent_at) FROM campaign_message_deliveries engagement_deliveries
      WHERE engagement_deliveries.account_id = contacts.account_id AND engagement_deliveries.source_id IS NOT NULL
        AND (engagement_deliveries.contact_id = contacts.id OR (
          contacts.phone_number IS NOT NULL
          AND RIGHT(regexp_replace(engagement_deliveries.phone_number, '\\D', '', 'g'), 10) =
              RIGHT(regexp_replace(contacts.phone_number, '\\D', '', 'g'), 10)))
    SQL
  }.freeze

  def initialize(account, user, params)
    @account = account
    # TODO: Change the order of arguments in FilterService maybe?
    # account, user, params makes more sense
    super(params, user)
  end

  def perform
    validate_query_operator
    @contacts = query_builder(@filters['contacts'])

    {
      contacts: @contacts,
      count: @contacts.count
    }
  end

  def filter_values(query_hash)
    return Array(query_hash['values']).map(&:to_i) if query_hash['attribute_key'] == 'inbox_id'

    current_val = query_hash['values'][0]
    if query_hash['attribute_key'] == 'phone_number'
      "+#{current_val&.delete('+')}"
    elsif query_hash['attribute_key'] == 'country_code'
      current_val.downcase
    else
      current_val.is_a?(String) ? current_val.downcase : current_val
    end
  end

  def base_relation
    @account.contacts.resolved_contacts(use_crm_v2: @account.feature_enabled?('crm_v2'))
  end

  def filter_config
    {
      entity: 'Contact',
      table_name: 'contacts'
    }
  end

  # Same date comparison as a regular column, applied to the engagement subquery instead
  def date_filter(current_filter, query_hash, filter_operator_value)
    expression = ENGAGEMENT_EXPRESSIONS[query_hash[:attribute_key]]
    return super unless current_filter['attribute_type'] == 'engagement' && expression

    "(#{expression})::date #{filter_operator_value} #{query_hash[:query_operator]}"
  end

  def build_condition_query_string(current_filter, query_hash, current_index)
    return super unless current_filter&.dig('attribute_type') == 'contact_inbox'

    contact_inbox_filter(query_hash, current_index)
  end

  private

  # A contact "belongs" to an inbox when it has a contact_inbox there (created on its first
  # conversation/template in that inbox). Contacts live account-wide, so this is the only link.
  def contact_inbox_filter(query_hash, current_index)
    @filter_values["value_#{current_index}"] = filter_values(query_hash)
    exists = 'EXISTS (SELECT 1 FROM contact_inboxes filter_contact_inboxes ' \
             'WHERE filter_contact_inboxes.contact_id = contacts.id ' \
             "AND filter_contact_inboxes.inbox_id IN (:value_#{current_index}))"
    exists = "NOT #{exists}" if query_hash[:filter_operator] == 'not_equal_to'

    "#{exists} #{query_hash[:query_operator]}"
  end

  def equals_to_filter_string(filter_operator, current_index)
    return "= :value_#{current_index}" if filter_operator == 'equal_to'

    "!= :value_#{current_index}"
  end
end
