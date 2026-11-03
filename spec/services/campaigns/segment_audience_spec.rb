require 'rails_helper'

RSpec.describe Campaigns::SegmentAudience do
  subject(:audience) { described_class.new(account: account, segment_id: segment.id) }

  let(:account) { create(:account) }
  let(:opt_out_key) { format(Redis::RedisKeys::WA_OPTED_OUT_PHONES, account_id: account.id) }
  let(:label) { create(:label, account: account, title: 'interesado') }
  let(:segment) do
    create(:custom_filter, account: account, user: create(:user, account: account), filter_type: :contact,
                           query: { payload: [{ attribute_key: 'labels', filter_operator: 'equal_to', values: [label.title], query_operator: nil }] })
  end

  after { Redis::Alfred.delete(opt_out_key) }

  def labeled_contact(**attrs)
    create(:contact, account: account, **attrs).tap { |contact| contact.update_labels([label.title]) }
  end

  it 'returns the segment contacts that can receive WhatsApp' do
    sendable = labeled_contact(phone_number: '+525511110001')
    labeled_contact(email: 'nophone@example.com')
    labeled_contact(phone_number: '+525511110002', additional_attributes: { 'wa_valid' => false })
    create(:contact, account: account, phone_number: '+525511110003')

    expect(audience.contacts).to contain_exactly(sendable)
  end

  it 'previews eligible and excluded counts the same way the send resolves them' do
    eligible = labeled_contact(phone_number: '+525511110001')
    labeled_contact(email: 'nophone@example.com')
    labeled_contact(phone_number: '+525511110002', additional_attributes: { 'wa_valid' => false })
    labeled_contact(phone_number: '+525511110003')
    Campaigns::RecipientEligibility.opt_out!(account.id, '+5215511110003')
    in_cooldown = labeled_contact(phone_number: '+525511110004')
    create(:campaign, account: account).campaign_message_deliveries.create!(
      account_id: account.id, audience_type: 'labels', contact_id: in_cooldown.id, phone_number: in_cooldown.phone_number,
      source_id: 'wamid.recent', status: 'sent', sent_at: 2.days.ago
    )

    preview = audience.preview

    expect(preview[:total]).to eq(5)
    expect(preview[:eligible]).to eq(1)
    expect(preview[:excluded]).to eq(no_phone: 1, wa_invalid: 1, opted_out: 1, cooldown: 1)
    expect(preview[:sample].pluck('id')).to eq([eligible.id])
  end

  it 'returns no contacts for a segment of another account' do
    other_segment = create(:custom_filter, filter_type: :contact, query: { payload: [] })

    expect(described_class.new(account: account, segment_id: other_segment.id).contacts).to be_empty
  end
end
