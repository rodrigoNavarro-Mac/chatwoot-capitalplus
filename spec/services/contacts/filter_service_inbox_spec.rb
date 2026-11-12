require 'rails_helper'

# "Entrada" filter (attribute_type "contact_inbox"): segment contacts by the inbox they have a
# contact_inbox in, so a WhatsApp campaign can target only one inbox's contacts (e.g. only Amura).
describe Contacts::FilterService do
  let(:account) { create(:account) }
  let(:fuego) { create(:inbox, account: account) }
  let(:amura) { create(:inbox, account: account) }
  let!(:fuego_contact) { create(:contact, :with_phone_number, account: account) }
  let!(:amura_contact) { create(:contact, :with_phone_number, account: account) }
  let!(:both_contact) { create(:contact, :with_phone_number, account: account) }
  let!(:no_inbox_contact) { create(:contact, :with_phone_number, account: account) }

  def filter(operator, values, extra = [])
    first = { attribute_key: 'inbox_id', filter_operator: operator, values: values, query_operator: extra.any? ? 'AND' : nil }
    payload = [first, *extra].map(&:with_indifferent_access)
    described_class.new(account, nil, { payload: payload }.with_indifferent_access).perform[:contacts]
  end

  before do
    create(:contact_inbox, contact: fuego_contact, inbox: fuego)
    create(:contact_inbox, contact: amura_contact, inbox: amura)
    create(:contact_inbox, contact: both_contact, inbox: fuego)
    create(:contact_inbox, contact: both_contact, inbox: amura)
  end

  it 'finds only the contacts of the selected inbox' do
    expect(filter('equal_to', [amura.id])).to contain_exactly(amura_contact, both_contact)
  end

  it 'accepts several inboxes and string ids as sent by the dashboard' do
    expect(filter('equal_to', [fuego.id.to_s, amura.id.to_s])).to contain_exactly(fuego_contact, amura_contact, both_contact)
  end

  it 'excludes the contacts of the selected inbox with not_equal_to' do
    expect(filter('not_equal_to', [amura.id])).to contain_exactly(fuego_contact, no_inbox_contact)
  end

  it 'combines with other conditions' do
    amura_contact.update!(name: 'Ana Amura')
    name_condition = { attribute_key: 'name', filter_operator: 'equal_to', values: ['ana amura'], query_operator: nil }

    expect(filter('equal_to', [amura.id], [name_condition])).to contain_exactly(amura_contact)
  end

  it 'feeds a campaign segment so it only targets that inbox contacts' do
    segment = create(:custom_filter, account: account, filter_type: :contact,
                                     query: { payload: [{ attribute_key: 'inbox_id', filter_operator: 'equal_to',
                                                          values: [amura.id], query_operator: nil }] })

    contacts = Campaigns::SegmentAudience.new(account: account, segment_id: segment.id).contacts

    expect(contacts).to contain_exactly(amura_contact, both_contact)
  end
end
