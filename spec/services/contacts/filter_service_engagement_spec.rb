require 'rails_helper'

# Engagement filters (attribute_type "engagement") used to build WhatsApp campaign segments
describe Contacts::FilterService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:replied_recently) { create(:contact, :with_phone_number, account: account) }
  let!(:replied_long_ago) { create(:contact, :with_phone_number, account: account) }
  let!(:never_replied) { create(:contact, :with_phone_number, account: account) }

  def message_from(contact, type, at)
    conversation = contact.conversations.first || create(:conversation, account: account, inbox: inbox, contact: contact)
    sender = type == :incoming ? contact : nil
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: type, sender: sender, created_at: at)
  end

  def filter(attribute_key, operator, values = [])
    payload = [{ attribute_key: attribute_key, filter_operator: operator, values: values, query_operator: nil }.with_indifferent_access]
    described_class.new(account, nil, { payload: payload }.with_indifferent_access).perform[:contacts]
  end

  before do
    message_from(replied_recently, :incoming, 2.days.ago)
    message_from(replied_long_ago, :incoming, 60.days.ago)
    message_from(never_replied, :outgoing, 10.days.ago)
  end

  describe 'last_replied_at' do
    it 'finds contacts that replied at some point' do
      expect(filter('last_replied_at', 'is_present')).to contain_exactly(replied_recently, replied_long_ago)
    end

    it 'finds contacts that never replied' do
      expect(filter('last_replied_at', 'is_not_present')).to contain_exactly(never_replied)
    end

    it 'finds contacts that have not replied in the last 30 days' do
      expect(filter('last_replied_at', 'days_before', ['30'])).to contain_exactly(replied_long_ago)
    end

    it 'finds contacts that replied after a date' do
      expect(filter('last_replied_at', 'is_greater_than', [10.days.ago.to_date.iso8601])).to contain_exactly(replied_recently)
    end
  end

  describe 'last_message_sent_at' do
    it 'finds contacts we have messaged' do
      expect(filter('last_message_sent_at', 'is_present')).to contain_exactly(never_replied)
    end
  end

  describe 'last_campaign_sent_at' do
    let(:campaign) { create(:campaign, account: account) }

    it 'matches CSV deliveries by the last 10 digits of the phone' do
      replied_recently.update!(phone_number: '+525511112222')
      campaign.campaign_message_deliveries.create!(
        account_id: account.id, audience_type: 'csv', phone_number: '+5215511112222',
        source_id: 'wamid.csv', status: 'sent', sent_at: 3.days.ago
      )

      expect(filter('last_campaign_sent_at', 'is_present')).to contain_exactly(replied_recently)
      expect(filter('last_campaign_sent_at', 'is_not_present')).to contain_exactly(replied_long_ago, never_replied)
    end

    it 'ignores attempts that never reached Meta' do
      campaign.campaign_message_deliveries.create!(
        account_id: account.id, audience_type: 'labels', contact_id: never_replied.id, phone_number: never_replied.phone_number,
        source_id: nil, status: 'failed'
      )

      expect(filter('last_campaign_sent_at', 'is_present')).to be_empty
    end
  end

  it 'rejects operators the engagement keys do not support' do
    expect { filter('last_replied_at', 'equal_to', ['x']) }.to raise_error(CustomExceptions::CustomFilter::InvalidOperator)
  end
end
