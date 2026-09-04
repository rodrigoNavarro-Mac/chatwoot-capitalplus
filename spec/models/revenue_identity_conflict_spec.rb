require 'rails_helper'

describe RevenueIdentityConflict do
  let(:account) { create(:account) }

  it 'is valid with an account and a known conflict_type' do
    conflict = described_class.new(account: account, conflict_type: 'multiple_candidates')

    expect(conflict).to be_valid
  end

  it 'rejects an unknown conflict_type' do
    conflict = described_class.new(account: account, conflict_type: 'something_else')

    expect(conflict).not_to be_valid
    expect(conflict.errors[:conflict_type]).to be_present
  end

  it 'defaults resolved to false' do
    conflict = described_class.create!(account: account, conflict_type: 'field_mismatch')

    expect(conflict.resolved).to be(false)
  end

  describe '.unresolved' do
    it 'returns only conflicts that have not been resolved' do
      unresolved = described_class.create!(account: account, conflict_type: 'field_mismatch')
      described_class.create!(account: account, conflict_type: 'field_mismatch', resolved: true)

      expect(account.revenue_identity_conflicts.unresolved).to contain_exactly(unresolved)
    end
  end
end
