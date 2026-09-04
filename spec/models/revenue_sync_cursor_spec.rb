require 'rails_helper'

describe RevenueSyncCursor do
  let(:account) { create(:account) }

  it 'is valid with an account and a known sync_type' do
    cursor = described_class.new(account: account, sync_type: 'leads')

    expect(cursor).to be_valid
  end

  it 'rejects an unknown sync_type' do
    cursor = described_class.new(account: account, sync_type: 'unknown')

    expect(cursor).not_to be_valid
    expect(cursor.errors[:sync_type]).to be_present
  end

  it 'does not allow two cursors with the same sync_type in the same account' do
    described_class.create!(account: account, sync_type: 'leads')
    duplicate = described_class.new(account: account, sync_type: 'leads')

    expect(duplicate).not_to be_valid
  end

  it 'allows the same sync_type across different accounts' do
    other_account = create(:account)
    described_class.create!(account: account, sync_type: 'leads')
    other = described_class.new(account: other_account, sync_type: 'leads')

    expect(other).to be_valid
  end
end
