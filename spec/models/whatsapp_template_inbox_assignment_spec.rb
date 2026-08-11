require 'rails_helper'

RSpec.describe WhatsappTemplateInboxAssignment do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: whatsapp_channel) }

  it 'is valid with an account, inbox and template_name' do
    assignment = described_class.new(account: account, inbox: inbox, template_name: 'promo_boutique')
    expect(assignment).to be_valid
  end

  it 'requires template_name' do
    assignment = described_class.new(account: account, inbox: inbox, template_name: nil)
    expect(assignment).not_to be_valid
    expect(assignment.errors[:template_name]).to be_present
  end

  it 'does not allow the same template_name to be assigned twice to the same inbox' do
    described_class.create!(account: account, inbox: inbox, template_name: 'promo_boutique')
    duplicate = described_class.new(account: account, inbox: inbox, template_name: 'promo_boutique')

    expect(duplicate).not_to be_valid
  end

  it 'allows the same template_name to be assigned to a different inbox' do
    other_channel = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
    other_inbox = create(:inbox, account: account, channel: other_channel)
    described_class.create!(account: account, inbox: inbox, template_name: 'promo_boutique')

    other_assignment = described_class.new(account: account, inbox: other_inbox, template_name: 'promo_boutique')

    expect(other_assignment).to be_valid
  end
end
