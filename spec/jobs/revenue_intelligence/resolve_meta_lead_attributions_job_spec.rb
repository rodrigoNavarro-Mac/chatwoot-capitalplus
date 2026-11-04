require 'rails_helper'

describe RevenueIntelligence::ResolveMetaLeadAttributionsJob do
  let(:account) { create(:account) }
  let(:client) { instance_double(Koala::Facebook::API) }
  let!(:hook) { create(:integrations_hook, :meta_lead_ads, account: account, status: 'enabled') }

  def create_lead(zoho_lead_id:, social_lead_id:, lead_source: 'Meta Ads', created_at_source: Time.zone.parse('2026-10-15'))
    account.revenue_leads.create!(zoho_lead_id: zoho_lead_id, lead_source: lead_source, social_lead_id: social_lead_id,
                                  created_at_source: created_at_source)
  end

  def confirmed_response(social_lead_id, created_at_source)
    { 'id' => social_lead_id, 'created_time' => created_at_source.iso8601, 'ad_id' => 'ad-1',
      'adset_id' => 'adset-1', 'campaign_id' => 'campaign-1', 'form_id' => 'form-1' }
  end

  before do
    allow(Koala::Facebook::API).to receive(:new).with(hook.access_token).and_return(client)
  end

  it 'uses the dedicated meta_lead_ads hook, never the shared meta_ads hook' do
    other_hook = create(:integrations_hook, :meta_ads, account: account, status: 'enabled')
    lead = create_lead(zoho_lead_id: 'lead-1', social_lead_id: '111')
    allow(client).to receive(:get_object).and_return(confirmed_response('111', lead.created_at_source))

    described_class.new.perform(account.id)

    expect(Koala::Facebook::API).not_to have_received(:new).with(other_hook.access_token)
  end

  it 'resolves an eligible lead and persists a confirmada attribution' do
    lead = create_lead(zoho_lead_id: 'lead-1', social_lead_id: '4582893005295147')
    allow(client).to receive(:get_object).and_return(confirmed_response('4582893005295147', lead.created_at_source))

    described_class.new.perform(account.id)

    attribution = lead.reload.meta_attribution
    expect(attribution).to have_attributes(verification_status: 'confirmada', meta_ad_id: 'ad-1', source: 'graph_api_leadgen_lookup')
  end

  it 'skips leads without a numeric social_lead_id (misma condición de elegibilidad de Fase 17/18)' do
    create_lead(zoho_lead_id: 'lead-1', social_lead_id: nil)
    create_lead(zoho_lead_id: 'lead-2', social_lead_id: 'texto-no-numerico')
    expect(client).not_to receive(:get_object)

    described_class.new.perform(account.id)
  end

  it 'skips leads from a different lead_source, even with a numeric social_lead_id' do
    create_lead(zoho_lead_id: 'lead-1', social_lead_id: '123456', lead_source: 'Google Ads')
    expect(client).not_to receive(:get_object)

    described_class.new.perform(account.id)
  end

  it 'is idempotent: a lead already confirmada is not re-queried on a second run' do
    lead = create_lead(zoho_lead_id: 'lead-1', social_lead_id: '111')
    allow(client).to receive(:get_object).and_return(confirmed_response('111', lead.created_at_source))
    described_class.new.perform(account.id)

    described_class.new.perform(account.id)

    expect(client).to have_received(:get_object).once
    expect(RevenueLeadMetaAttribution.where(revenue_lead: lead).count).to eq(1)
  end

  it 'retries a lead left in pendiente on a later run (nunca se atasca ahí sin reintentar)' do
    lead = create_lead(zoho_lead_id: 'lead-1', social_lead_id: '111')
    account.revenue_lead_meta_attributions.create!(revenue_lead: lead, social_lead_id: '111') # pendiente, sin intento todavía
    allow(client).to receive(:get_object).and_return(confirmed_response('111', lead.created_at_source))

    described_class.new.perform(account.id)

    expect(lead.reload.meta_attribution).to be_confirmada
  end

  it 'persists a permissions-blocked result without raising, and does not mark it as no_correspondiente' do
    lead = create_lead(zoho_lead_id: 'lead-1', social_lead_id: '111')
    error = Koala::Facebook::ClientError.new(400, '', { 'code' => 100, 'error_subcode' => 33, 'message' => 'blocked' })
    allow(client).to receive(:get_object).and_raise(error)

    expect { described_class.new.perform(account.id) }.not_to raise_error

    expect(lead.reload.meta_attribution.verification_status).to eq('no_verificable_permisos_o_ausencia')
  end

  it 'continues with other hooks/accounts when one hook raises unexpectedly' do
    other_account = create(:account)
    other_hook = create(:integrations_hook, :meta_lead_ads, account: other_account, status: 'enabled')
    other_client = instance_double(Koala::Facebook::API)
    allow(Koala::Facebook::API).to receive(:new).with(other_hook.access_token).and_return(other_client)
    allow(Koala::Facebook::API).to receive(:new).with(hook.access_token).and_raise(StandardError, 'boom inesperado')
    create_lead(zoho_lead_id: 'lead-1', social_lead_id: '111')
    other_lead = other_account.revenue_leads.create!(zoho_lead_id: 'lead-1', lead_source: 'Meta Ads', social_lead_id: '222',
                                                     created_at_source: Time.zone.parse('2026-10-15'))
    allow(other_client).to receive(:get_object).and_return(confirmed_response('222', other_lead.created_at_source))

    expect { described_class.new.perform }.not_to raise_error

    expect(other_lead.reload.meta_attribution).to be_confirmada
  end

  # Fase 22 §2: aislamiento por cuenta -- un lead de otra cuenta nunca debe resolverse al correr
  # el job acotado a una cuenta específica (el Hook de la otra cuenta ni siquiera se considera).
  it 'never processes leads from a different account when scoped to one account_id' do
    other_account = create(:account)
    other_hook = create(:integrations_hook, :meta_lead_ads, account: other_account, status: 'enabled')
    other_client = instance_double(Koala::Facebook::API)
    allow(Koala::Facebook::API).to receive(:new).with(other_hook.access_token).and_return(other_client)
    allow(other_client).to receive(:get_object)
    other_account.revenue_leads.create!(zoho_lead_id: 'lead-1', lead_source: 'Meta Ads', social_lead_id: '111')

    described_class.new.perform(account.id)

    expect(other_client).not_to have_received(:get_object)
    expect(RevenueLeadMetaAttribution.count).to eq(0)
  end

  # Fase 22 §5/§1: nunca toca los campos históricos de texto libre de Zoho.
  it 'never overwrites revenue_leads.adset_id/advert_id (siguen siendo texto libre de Zoho)' do
    lead = create_lead(zoho_lead_id: 'lead-1', social_lead_id: '111')
    lead.update!(adset_id: 'Nombre original Zoho', advert_id: 'Nombre original Zoho')
    allow(client).to receive(:get_object).and_return(confirmed_response('111', lead.created_at_source))

    described_class.new.perform(account.id)

    lead.reload
    expect(lead.adset_id).to eq('Nombre original Zoho')
    expect(lead.advert_id).to eq('Nombre original Zoho')
  end

  it 'respects batch_size, leaving the rest pendiente/untouched for a later run' do
    lead_a = create_lead(zoho_lead_id: 'lead-a', social_lead_id: '111')
    create_lead(zoho_lead_id: 'lead-b', social_lead_id: '222')
    allow(client).to receive(:get_object).and_return(confirmed_response('111', lead_a.created_at_source))

    described_class.new.perform(account.id, batch_size: 1)

    expect(RevenueLeadMetaAttribution.count).to eq(1)
  end
end
