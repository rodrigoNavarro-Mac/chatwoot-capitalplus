require 'rails_helper'

describe RevenueLeadMetaAttribution do
  let(:account) { create(:account) }
  let(:lead) { account.revenue_leads.create!(zoho_lead_id: 'lead-1', lead_source: 'Meta Ads', social_lead_id: '4582893005295147') }

  def build_attribution(**attrs)
    account.revenue_lead_meta_attributions.new({ revenue_lead: lead, social_lead_id: lead.social_lead_id }.merge(attrs))
  end

  describe 'validations' do
    it 'is valid in the default pendiente state, without fetched_at' do
      attribution = build_attribution
      expect(attribution.verification_status).to eq('pendiente')
      expect(attribution).to be_valid
    end

    it 'requires social_lead_id' do
      expect(build_attribution(social_lead_id: nil)).to be_invalid
    end

    it 'only accepts the known verification_status vocabulary' do
      expect(build_attribution(verification_status: 'confirmada', fetched_at: Time.current)).to be_valid
      expect(build_attribution(verification_status: 'algo_inventado')).to be_invalid
    end

    # Fase 22 §2: corrección explícita -- fetched_at NO se exige en estado pendiente.
    it 'does not require fetched_at while pendiente' do
      attribution = build_attribution(verification_status: 'pendiente', fetched_at: nil)
      expect(attribution).to be_valid
    end

    %w[confirmada parcialmente_verificable no_correspondiente no_verificable_permisos_o_ausencia no_verificable_otro_error].each do |status|
      it "requires fetched_at once verification_status is '#{status}'" do
        attribution = build_attribution(verification_status: status, fetched_at: nil)
        expect(attribution).to be_invalid
        expect(attribution.errors[:fetched_at]).to be_present
      end
    end

    it 'enforces one attribution per revenue_lead (1:1)' do
      build_attribution.save!
      expect(build_attribution).to be_invalid
    end

    # Fase 22 §2: aislamiento por cuenta -- nunca debe poder crearse una atribución cuyo
    # account_id no coincida con el account_id real del revenue_lead referenciado.
    it 'rejects an attribution whose account_id does not match the referenced revenue_lead account_id' do
      other_account = create(:account)
      attribution = described_class.new(account_id: other_account.id, revenue_lead: lead, social_lead_id: lead.social_lead_id)

      expect(attribution).to be_invalid
      expect(attribution.errors[:account_id]).to be_present
    end
  end

  describe 'scopes' do
    it '.confirmada / .pendiente / .no_verificable split records by status' do
      confirmed = build_attribution(verification_status: 'confirmada', fetched_at: Time.current).tap(&:save!)
      pending_one = account.revenue_lead_meta_attributions.create!(
        revenue_lead: account.revenue_leads.create!(zoho_lead_id: 'lead-2', social_lead_id: '111'), social_lead_id: '111'
      )
      blocked = account.revenue_lead_meta_attributions.create!(
        revenue_lead: account.revenue_leads.create!(zoho_lead_id: 'lead-3', social_lead_id: '222'), social_lead_id: '222',
        verification_status: 'no_verificable_permisos_o_ausencia', fetched_at: Time.current
      )

      expect(described_class.confirmada).to contain_exactly(confirmed)
      expect(described_class.pendiente).to contain_exactly(pending_one)
      expect(described_class.no_verificable).to contain_exactly(blocked)
    end
  end

  describe '#confirmada?' do
    it 'is true only for the confirmada status' do
      expect(build_attribution(verification_status: 'confirmada', fetched_at: Time.current)).to be_confirmada
      expect(build_attribution(verification_status: 'parcialmente_verificable', fetched_at: Time.current)).not_to be_confirmada
    end
  end

  # Fase 22 §1/§5: protección explícita de los campos históricos de Zoho -- esta tabla nunca debe
  # ser capaz de alterar revenue_leads.adset_id/advert_id, ni por accidente de asociación.
  describe 'protección de los campos históricos de Zoho en revenue_leads' do
    it 'persisting an attribution never changes revenue_leads.adset_id/advert_id' do
      lead.update!(adset_id: 'Nombre Adset Original', advert_id: 'Nombre Anuncio Original')

      build_attribution(
        verification_status: 'confirmada', fetched_at: Time.current,
        meta_ad_id: '999', meta_adset_id: '888', meta_campaign_id: '777'
      ).save!

      lead.reload
      expect(lead.adset_id).to eq('Nombre Adset Original')
      expect(lead.advert_id).to eq('Nombre Anuncio Original')
    end
  end
end
