require 'rails_helper'

describe RevenueIntelligence::SyncMetaAdsSpendJob do
  def insight_row(campaign_name: 'Fuego 11 Abril', adset_name: 'Adset 1', ad_name: 'Ad 1', spend: '123.45', date_start: '2026-09-20')
    { 'campaign_name' => campaign_name, 'adset_name' => adset_name, 'ad_name' => ad_name, 'spend' => spend, 'date_start' => date_start }
  end

  describe 'lógica del job (mockeando Koala::Facebook::API directo)' do
    let(:account) { create(:account) }
    let(:client) { instance_double(Koala::Facebook::API) }
    let!(:hook) { create(:integrations_hook, :meta_ads, account: account, status: 'enabled') }

    def page_of(rows, next_page: nil)
      collection = rows.dup
      collection.define_singleton_method(:next_page) { next_page }
      collection
    end

    def stub_currency(a_client, ad_account_id, currency: 'MXN')
      allow(a_client).to receive(:get_object).with(ad_account_id, { fields: 'currency' }, { api_version: described_class::GRAPH_API_VERSION })
                                             .and_return({ 'currency' => currency })
    end

    before do
      allow(Koala::Facebook::API).to receive(:new).with(hook.access_token).and_return(client)
      stub_currency(client, 'act_123456789')
    end

    it 'creates a meta_api-sourced revenue_ad_spend row per insight row' do
      allow(client).to receive(:graph_call).and_return(page_of([insight_row]))

      described_class.new.perform(account.id)

      spend = account.revenue_ad_spends.sole
      expect(spend).to have_attributes(
        campaign_name: 'Fuego 11 Abril', adset_name: 'Adset 1', advert_name: 'Ad 1',
        amount: 123.45, currency: 'MXN', source: 'meta_api',
        period_start: Date.parse('2026-09-20'), period_end: Date.parse('2026-09-20')
      )
    end

    it 'normalizes an ad_account_id missing the act_ prefix (real production incident: Graph API error_subcode 33 without it)' do
      hook.update!(settings: { 'ad_account_id' => '123456789' })
      allow(client).to receive(:graph_call).and_return(page_of([insight_row]))

      described_class.new.perform(account.id)

      expect(client).to have_received(:get_object).with('act_123456789', anything, anything)
      expect(client).to have_received(:graph_call).with('act_123456789/insights', anything, anything, anything)
      expect(account.revenue_ad_spends.count).to eq(1)
    end

    it 'always pins an explicit Graph API version, never the unversioned default Meta now rejects (production incident: OAuthException 2635)' do
      allow(client).to receive(:graph_call).and_return(page_of([insight_row]))

      described_class.new.perform(account.id)

      expect(client).to have_received(:get_object).with(anything, anything, { api_version: 'v25.0' })
      expect(client).to have_received(:graph_call).with(anything, anything, 'get', { api_version: 'v25.0' })
    end

    it 'calls graph_call (parsed), never the raw api method (production incident: NoMethodError on Koala::HTTPService::Response)' do
      allow(client).to receive(:graph_call).and_return(page_of([insight_row]))
      expect(client).not_to receive(:api)

      described_class.new.perform(account.id)
    end

    it 'follows pagination until next_page is nil' do
      second_page = page_of([insight_row(ad_name: 'Ad 2', date_start: '2026-09-21')])
      allow(client).to receive(:graph_call).and_return(page_of([insight_row(ad_name: 'Ad 1')], next_page: second_page))

      described_class.new.perform(account.id)

      expect(account.revenue_ad_spends.pluck(:advert_name)).to contain_exactly('Ad 1', 'Ad 2')
    end

    it 'is idempotent: re-running updates the same row instead of duplicating it' do
      allow(client).to receive(:graph_call).and_return(page_of([insight_row(spend: '100.00')]))
      described_class.new.perform(account.id)

      allow(client).to receive(:graph_call).and_return(page_of([insight_row(spend: '150.00')]))
      described_class.new.perform(account.id)

      expect(account.revenue_ad_spends.count).to eq(1)
      expect(account.revenue_ad_spends.sole.amount).to eq(150.00)
    end

    it 'automatico manda: overwrites a manual row that exists for the exact same day/campaign/adset/anuncio' do
      account.revenue_ad_spends.create!(campaign_name: 'Fuego 11 Abril', adset_name: 'Adset 1', advert_name: 'Ad 1',
                                        period_start: '2026-09-20', period_end: '2026-09-20', amount: 999, source: 'manual')
      allow(client).to receive(:graph_call).and_return(page_of([insight_row(spend: '123.45')]))

      described_class.new.perform(account.id)

      spend = account.revenue_ad_spends.sole
      expect(spend.source).to eq('meta_api')
      expect(spend.amount).to eq(123.45)
    end

    it 'does not touch a manual row for a different period (coarser capture)' do
      manual = account.revenue_ad_spends.create!(campaign_name: 'Fuego 11 Abril', adset_name: nil, advert_name: nil,
                                                 period_start: '2026-09-01', period_end: '2026-09-30', amount: 5000, source: 'manual')
      allow(client).to receive(:graph_call).and_return(page_of([insight_row]))

      described_class.new.perform(account.id)

      expect(manual.reload.source).to eq('manual')
      expect(account.revenue_ad_spends.count).to eq(2)
    end

    it 'aborts the sync for a hook whose ad account currency is not MXN, without raising' do
      stub_currency(client, 'act_123456789', currency: 'USD')
      expect(client).not_to receive(:graph_call)

      expect { described_class.new.perform(account.id) }.not_to raise_error
      expect(account.revenue_ad_spends.count).to eq(0)
    end

    it 'skips a hook without ad_account_id configured' do
      # update_column salta la validación de settings_json_schema (ad_account_id required) --
      # simula un dato heredado/corrupto, no un estado alcanzable hoy vía el formulario.
      hook.update_column(:settings, {}) # rubocop:disable Rails/SkipsModelValidations
      expect(client).not_to receive(:graph_call)

      described_class.new.perform(account.id)
    end

    it 'continues with other hooks when one hook raises' do
      other_account = create(:account)
      other_hook = create(:integrations_hook, :meta_ads, account: other_account, status: 'enabled',
                                                         settings: { 'ad_account_id' => 'act_987654321' })
      other_client = instance_double(Koala::Facebook::API)
      allow(Koala::Facebook::API).to receive(:new).with(other_hook.access_token).and_return(other_client)
      allow(client).to receive(:get_object).and_raise(Koala::Facebook::ClientError.new(400, '', {}))
      stub_currency(other_client, 'act_987654321')
      allow(other_client).to receive(:graph_call).and_return(page_of([insight_row]))

      expect { described_class.new.perform }.not_to raise_error

      expect(other_account.revenue_ad_spends.count).to eq(1)
    end
  end

  # Los tests de arriba stubean Koala::Facebook::API directo -- eso prueba la lógica del job, pero
  # NO habría detectado el bug real de producción de usar #api (HTTP crudo, sin parsear) en vez de
  # #graph_call (lo que get_object usa internamente): ambos son métodos reales y válidos de
  # Koala::Facebook::API, así que un instance_double no distingue "el método correcto" de "un
  # método que existe". Este context aparte (sin el before de arriba que mockea
  # Koala::Facebook::API.new) stubea al nivel de HTTP (WebMock, mismo patrón que
  # sync_zoho_leads_job_spec.rb) y deja correr el parsing/paginación real de Koala -- sí habría
  # detectado ese bug.
  describe 'contra el cliente real de Koala (WebMock, sin mockear Koala)' do
    let(:account) { create(:account) }

    before do
      create(:integrations_hook, :meta_ads, account: account, status: 'enabled',
                                            settings: { 'ad_account_id' => 'act_123456789' })
    end

    it 'trae y guarda el gasto real parseado desde la respuesta HTTP de Meta, incluida la paginación' do
      stub_request(:get, %r{graph\.facebook\.com/v25\.0/act_123456789(?!/insights)})
        .to_return(status: 200, body: { currency: 'MXN' }.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, %r{graph\.facebook\.com/v25\.0/act_123456789/insights})
        .to_return(
          { status: 200,
            body: { data: [insight_row(ad_name: 'Ad 1')],
                    paging: { next: 'https://graph.facebook.com/v25.0/act_123456789/insights?after=cursor1' } }.to_json,
            headers: { 'Content-Type' => 'application/json' } },
          { status: 200, body: { data: [insight_row(ad_name: 'Ad 2', date_start: '2026-09-21')] }.to_json,
            headers: { 'Content-Type' => 'application/json' } }
        )

      described_class.new.perform(account.id)

      expect(account.revenue_ad_spends.pluck(:advert_name)).to contain_exactly('Ad 1', 'Ad 2')
      expect(account.revenue_ad_spends.first).to have_attributes(source: 'meta_api', currency: 'MXN')
    end
  end
end
