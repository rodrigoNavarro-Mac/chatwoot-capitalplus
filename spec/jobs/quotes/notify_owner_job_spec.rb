require 'rails_helper'

RSpec.describe Quotes::NotifyOwnerJob do
  let(:account) { create(:account) }

  it 'sends the quote to the resolved owner email' do
    quote = create(:quote, account: account, status: 'completed', source_type: 'deal', zoho_deal_id: 'D1',
                           deal_snapshot: { 'Owner' => { 'email' => 'owner@example.com' } })
    mail = instance_double(ActionMailer::MessageDelivery, deliver_later: true)
    allow(QuoteMailer).to receive(:with).and_return(QuoteMailer)
    allow(QuoteMailer).to receive(:notify_owner).with(quote, to: 'owner@example.com').and_return(mail)

    described_class.new.perform(quote.id)

    expect(mail).to have_received(:deliver_later)
  end

  it 'does nothing when no owner email can be resolved' do
    quote = create(:quote, account: account, status: 'completed', source_type: 'deal', zoho_deal_id: 'D1', deal_snapshot: {})

    expect(QuoteMailer).not_to receive(:with)
    described_class.new.perform(quote.id)
  end

  it 'does nothing when the quote is not completed' do
    quote = create(:quote, account: account, status: 'failed', source_type: 'deal', zoho_deal_id: 'D1')

    expect(Quotes::ResolveOwnerEmailService).not_to receive(:call)
    described_class.new.perform(quote.id)
  end

  it 'does nothing when the quote no longer exists' do
    expect(Quotes::ResolveOwnerEmailService).not_to receive(:call)
    described_class.new.perform(-1)
  end
end
