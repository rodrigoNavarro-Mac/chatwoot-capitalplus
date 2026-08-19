require 'rails_helper'

RSpec.describe RecordShare, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:shareable) }
    it { is_expected.to belong_to(:shared_with) }
    it { is_expected.to belong_to(:shared_by).class_name('User') }
  end

  describe 'validations' do
    let(:account) { create(:account) }
    let(:conversation) { create(:conversation, account: account) }
    let(:user) { create(:user, account: account) }

    it 'is valid with a conversation shared with a user' do
      share = described_class.new(
        account: account,
        shareable: conversation,
        shared_with: user,
        shared_by: user,
        access_level: :view
      )
      expect(share).to be_valid
    end

    it 'rejects an unsupported shareable_type' do
      share = described_class.new(
        account: account,
        shareable_type: 'Account',
        shareable_id: account.id,
        shared_with: user,
        shared_by: user
      )
      expect(share).not_to be_valid
    end

    it 'rejects duplicate shares for the same record and recipient' do
      described_class.create!(account: account, shareable: conversation, shared_with: user, shared_by: user)
      duplicate = described_class.new(account: account, shareable: conversation, shared_with: user, shared_by: user)

      expect(duplicate).not_to be_valid
    end
  end
end
