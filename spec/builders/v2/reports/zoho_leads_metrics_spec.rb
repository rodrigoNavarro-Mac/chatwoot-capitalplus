require 'rails_helper'

describe V2::Reports::ZohoLeadsMetrics do
  subject(:metrics) { described_class.new(account: account, development_key: 'Fuego', range: range, inbox: inbox) }

  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp_channel.inbox }
  let(:range) { Time.zone.parse('2026-08-03T00:00:00Z')...Time.zone.parse('2026-08-10T00:00:00Z') }

  def stub_leads(leads)
    fake_service = instance_double(Crm::Zoho::LeadsForPeriodService, fetch: leads)
    allow(Crm::Zoho::LeadsForPeriodService).to receive(:new)
      .with(account: account, development_key: 'Fuego', range: range)
      .and_return(fake_service)
  end

  def stub_deals(deals)
    fake_service = instance_double(Crm::Zoho::DealsForPeriodService, fetch: deals)
    allow(Crm::Zoho::DealsForPeriodService).to receive(:new)
      .with(account: account, development_key: 'Fuego', range: range)
      .and_return(fake_service)
  end

  describe '#summary' do
    it 'is nil when there are no leads' do
      stub_leads([])

      expect(metrics.summary).to be_nil
    end

    context 'with a mix of statuses, sources and owners' do
      subject(:summary) do
        stub_leads([
                     { 'Lead_Status' => 'Contacted', 'Lead_Source' => 'Facebook Ads', 'Owner' => { 'name' => 'Eunice' } },
                     { 'Lead_Status' => 'Contacted', 'Lead_Source' => 'Facebook Ads', 'Owner' => { 'name' => 'Eunice' } },
                     { 'Lead_Status' => 'Attempted to Contact', 'Lead_Source' => 'Google Ads', 'Owner' => { 'name' => 'Carlos' } },
                     { 'Lead_Status' => 'Lost Lead', 'Lead_Source' => 'Facebook Ads', 'Raz_n_de_descarte' => 'NO TUVO PRESUPUESTO',
                       'Owner' => { 'name' => 'Eunice' } }
                   ])
        metrics.summary
      end

      it 'summarizes status, source, discard reasons and quality totals' do
        expect(summary[:total]).to eq(4)
        expect(summary[:by_status]).to eq('Contactado' => 2, 'Intento de contacto' => 1, 'Cliente perdido/Descartado' => 1)
        expect(summary[:by_source]).to eq('Facebook Ads' => 3, 'Google Ads' => 1)
        expect(summary[:discard_reasons]).to eq('NO TUVO PRESUPUESTO' => 1)
        expect(summary[:quality_leads_count]).to eq(2)
        expect(summary[:quality_leads_percent]).to eq(50.0)
      end

      it 'summarizes leads by owner' do
        expect(summary[:by_owner]).to eq('Eunice' => 3, 'Carlos' => 1)
      end

      it 'summarizes quality (contacted) leads by source' do
        expect(summary[:quality_by_source]).to eq(
          'Facebook Ads' => { total: 3, quality: 2 },
          'Google Ads' => { total: 1, quality: 0 }
        )
      end
    end
  end

  describe '#deals_created' do
    it 'is nil when development_key or range is blank' do
      metrics_without_key = described_class.new(account: account, development_key: nil, range: range, inbox: inbox)

      expect(metrics_without_key.deals_created).to be_nil
    end

    it 'reports total deals created and the conversion rate against total leads' do
      stub_leads([{ 'Lead_Status' => 'Contacted' }, { 'Lead_Status' => 'Contacted' }, { 'Lead_Status' => 'Lost Lead' },
                  { 'Lead_Status' => 'Lost Lead' }])
      stub_deals([{ 'id' => 'deal-1' }])

      result = metrics.deals_created

      expect(result).to eq(total: 1, conversion_rate: 25.0)
    end
  end

  describe '#conversion_totals' do
    it 'is nil when there are no leads or deals' do
      stub_leads([])
      stub_deals([])

      expect(metrics.conversion_totals).to be_nil
    end

    it 'counts converted (deals created) and lost (Lead_Status Lost Lead) for the whole desarrollo, not by owner' do
      # Lead_Status "Contacted" NO cuenta como convertido -- solo si se le creo un Deal. El Owner
      # de cada lead/deal no importa aqui -- es un total del desarrollo, no un desglose por asesor.
      stub_leads([
                   { 'Lead_Status' => 'Contacted', 'Owner' => { 'name' => 'Eunice' } },
                   { 'Lead_Status' => 'Lost Lead', 'Owner' => { 'name' => 'Eunice' } },
                   { 'Lead_Status' => 'Attempted to Contact', 'Owner' => nil }
                 ])
      stub_deals([
                   { 'id' => 'deal-1', 'Owner' => { 'name' => 'Eunice' } },
                   { 'id' => 'deal-2', 'Owner' => { 'name' => 'Carlos' } }
                 ])

      result = metrics.conversion_totals

      expect(result).to eq(converted: 2, lost: 1)
    end
  end

  describe '#schedule_distribution' do
    it 'is nil when there are no leads' do
      stub_leads([])

      expect(metrics.schedule_distribution).to be_nil
    end

    it 'classifies leads by whether their Created_Time falls within the inbox working hours' do
      create(:working_hour, inbox: inbox, day_of_week: 1, open_hour: 9, open_minutes: 0, close_hour: 17, close_minutes: 0)
      stub_leads([
                   { 'Created_Time' => '2026-08-03T12:00:00Z' }, # lunes, dentro
                   { 'Created_Time' => '2026-08-03T22:00:00Z' }, # lunes, fuera
                   { 'Created_Time' => nil }
                 ])

      result = metrics.schedule_distribution

      expect(result).to eq(within_business_hours: 1, outside_business_hours: 2, total: 3)
    end
  end

  describe '#leads' do
    it 'memoizes the Zoho fetch so calling it repeatedly only hits the API once' do
      fake_service = instance_double(Crm::Zoho::LeadsForPeriodService, fetch: [{ 'id' => '1' }])
      allow(Crm::Zoho::LeadsForPeriodService).to receive(:new).and_return(fake_service)

      2.times { metrics.leads }

      expect(fake_service).to have_received(:fetch).once
    end
  end
end
