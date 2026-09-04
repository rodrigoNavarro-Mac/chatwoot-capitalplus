require 'rails_helper'

describe RevenueIntelligence::ExtractCallFeaturesJob do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:revenue_contact) do
    account.revenue_contacts.create!(chatwoot_contact_id: contact.id, first_seen_at: Time.current, last_seen_at: Time.current)
  end
  let(:call) { create(:call, account: account, conversation: conversation, contact: contact, status: 'completed', started_at: Time.current) }

  before do
    account.enable_features!('crm_integration')
    create(:integrations_hook, :zoho_crm, account: account, status: 'enabled')
  end

  describe '#perform' do
    it 'flattens qualification_map into qual_* boolean columns and counts captured keys' do
      create(:call_analysis, call: call, account: account, status: 'completed',
                             qualification_map: {
                               'presupuesto' => { 'captured' => true, 'evidence' => 'sí tiene' },
                               'momento_compra' => { 'captured' => true, 'evidence' => 'ya' },
                               'necesidad_concreta' => { 'captured' => false, 'evidence' => nil }
                             })

      described_class.new.perform

      feature = account.revenue_call_features.find_by(call_id: call.id)
      expect(feature.qual_presupuesto).to be(true)
      expect(feature.qual_momento_compra).to be(true)
      expect(feature.qual_necesidad_concreta).to be(false)
      expect(feature.qual_siguiente_paso).to be(false) # ausente del jsonb -> false, no error
      expect(feature.qualification_count).to eq(2)
      expect(feature.qualification_completeness).to eq(0.2) # 2/10
    end

    context 'with metrics, objections and risks on the analysis' do
      let!(:analysis) do
        create(:call_analysis, call: call, account: account, status: 'completed',
                               metrics: { 'talk_ratio' => 0.6, 'longest_monologue_seconds' => 45,
                                          'questions' => { 'open' => 3, 'closed' => 1 }, 'cta_used' => true },
                               objections: [{ 'category' => 'financiera' }, { 'category' => 'producto' }],
                               risks: [{ 'type' => 'urgencia_antes_de_valor' }])
      end
      let(:feature) { account.revenue_call_features.find_by(call_id: call.id) }

      before { described_class.new.perform }

      it 'flattens metrics into plain columns' do
        expect(feature.talk_ratio.to_f).to eq(0.6)
        expect(feature.longest_monologue_seconds).to eq(45)
        expect(feature.open_questions).to eq(3)
        expect(feature.closed_questions).to eq(1)
        expect(feature.cta_used).to be(true)
      end

      it 'counts objections/risks and links call_analysis_id' do
        expect(feature.objection_count).to eq(2)
        expect(feature.risk_count).to eq(1)
        expect(feature.call_analysis_id).to eq(analysis.id)
      end
    end

    it 'copies score_total/score_reading from the scorecard, and links revenue_contact_id via the call contact' do
      create(:call_analysis, call: call, account: account, status: 'completed', scorecard: { 'total_score' => 88.5, 'reading' => 'solido' })

      described_class.new.perform

      feature = account.revenue_call_features.find_by(call_id: call.id)
      expect(feature.score_total.to_f).to eq(88.5)
      expect(feature.score_reading).to eq('solido')
      expect(feature.revenue_contact_id).to eq(revenue_contact.id)
    end

    it 'is idempotent — running it twice does not duplicate, and updates in place if the analysis changes' do
      create(:call_analysis, call: call, account: account, status: 'completed', scorecard: { 'total_score' => 50.0 })
      described_class.new.perform
      CallAnalysis.find_by(call_id: call.id).update!(scorecard: { 'total_score' => 90.0 })

      described_class.new.perform

      expect(account.revenue_call_features.where(call_id: call.id).count).to eq(1)
      expect(account.revenue_call_features.find_by(call_id: call.id).score_total.to_f).to eq(90.0)
    end

    it 'does not create a feature for a pending (not completed) analysis' do
      create(:call_analysis, call: call, account: account, status: 'pending')

      described_class.new.perform

      expect(account.revenue_call_features.where(call_id: call.id)).to be_empty
    end

    it 'continues with other analyses when one raises' do
      broken_call = create(:call, account: account, conversation: conversation, contact: contact, status: 'completed')
      create(:call_analysis, call: broken_call, account: account, status: 'completed')
      create(:call_analysis, call: call, account: account, status: 'completed')
      allow_any_instance_of(described_class).to receive(:upsert_feature).and_wrap_original do |method, acc, analysis, contacts| # rubocop:disable RSpec/AnyInstance
        raise 'boom' if analysis.call_id == broken_call.id

        method.call(acc, analysis, contacts)
      end

      expect { described_class.new.perform }.not_to raise_error
      expect(account.revenue_call_features.find_by(call_id: call.id)).to be_present
    end

    it 'only extracts features for the given account when an account_id is passed' do
      other_account = create(:account)
      other_account.enable_features!('crm_integration')
      create(:integrations_hook, :zoho_crm, account: other_account, status: 'enabled')
      other_conversation = create(:conversation, account: other_account)
      other_call = create(:call, account: other_account, conversation: other_conversation, contact: other_conversation.contact,
                                 status: 'completed')
      create(:call_analysis, call: other_call, account: other_account, status: 'completed')
      create(:call_analysis, call: call, account: account, status: 'completed')

      described_class.new.perform(account.id)

      expect(account.revenue_call_features.where(call_id: call.id)).to exist
      expect(other_account.revenue_call_features.where(call_id: other_call.id)).to be_empty
    end
  end
end
