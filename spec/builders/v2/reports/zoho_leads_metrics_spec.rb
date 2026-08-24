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
      # Lead_Status llega de la API ya en español ("Contactado", no "Contacted") -- ver comentario
      # de LOST_LEAD_STATUS/CONTACTED_STATUS. Fixtures con los valores reales, no los asumidos.
      # Created_Time dentro del range ('2026-08-03'..'2026-08-10') -> lead nuevo del periodo;
      # anterior al range -> lead viejo en seguimiento (ver #new_count/#follow_up_count).
      subject(:summary) do
        stub_leads([
                     { 'Lead_Status' => 'Contactado', 'Lead_Source' => 'Facebook Ads', 'Owner' => { 'name' => 'Eunice' },
                       'Created_Time' => '2026-08-04T10:00:00Z' },
                     { 'Lead_Status' => 'Contactado', 'Lead_Source' => 'Facebook Ads', 'Owner' => { 'name' => 'Eunice' },
                       'Created_Time' => '2026-08-05T10:00:00Z' },
                     { 'Lead_Status' => 'Intento de contacto', 'Lead_Source' => 'Google Ads', 'Owner' => { 'name' => 'Carlos' },
                       'Created_Time' => '2026-07-01T10:00:00Z' },
                     { 'Lead_Status' => 'Cliente perdido/Descartado', 'Lead_Source' => 'Facebook Ads',
                       'Raz_n_de_descarte' => 'NO TUVO PRESUPUESTO', 'Owner' => { 'name' => 'Eunice' },
                       'Created_Time' => '2026-07-01T10:00:00Z' }
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

      it 'splits by_status into new leads (Created_Time in range) vs follow-up (created before)' do
        expect(summary[:new_count]).to eq(2)
        expect(summary[:follow_up_count]).to eq(2)
        expect(summary[:by_status_new]).to eq('Contactado' => 2)
        expect(summary[:by_status_follow_up]).to eq('Intento de contacto' => 1, 'Cliente perdido/Descartado' => 1)
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

    context 'when a lead has no Created_Time' do
      it 'treats it as follow-up, not new' do
        stub_leads([{ 'Lead_Status' => 'Contactado' }])

        expect(metrics.summary[:new_count]).to eq(0)
        expect(metrics.summary[:follow_up_count]).to eq(1)
      end
    end
  end

  describe '#deals_created' do
    it 'is nil when development_key or range is blank' do
      metrics_without_key = described_class.new(account: account, development_key: nil, range: range, inbox: inbox)

      expect(metrics_without_key.deals_created).to be_nil
    end

    it 'reports total deals created and the conversion rate against NEW leads (Created_Time in range)' do
      stub_leads([
                   { 'Lead_Status' => 'Contactado', 'Created_Time' => '2026-08-04T10:00:00Z' },
                   { 'Lead_Status' => 'Contactado', 'Created_Time' => '2026-08-05T10:00:00Z' },
                   { 'Lead_Status' => 'Cliente perdido/Descartado', 'Created_Time' => '2026-08-06T10:00:00Z' },
                   { 'Lead_Status' => 'Cliente perdido/Descartado', 'Created_Time' => '2026-07-01T10:00:00Z' } # seguimiento, no cuenta
                 ])
      stub_deals([{ 'id' => 'deal-1' }])

      result = metrics.deals_created

      expect(result).to eq(total: 1, conversion_rate: 33.33)
    end
  end

  describe '#deals_activity' do
    it 'is nil when development_key or range is blank' do
      metrics_without_key = described_class.new(account: account, development_key: nil, range: range, inbox: inbox)

      expect(metrics_without_key.deals_activity).to be_nil
    end

    it 'is nil when there are no deals created in the period' do
      stub_deals([])

      expect(metrics.deals_activity).to be_nil
    end

    # Caso real detectado 2026-08-24: un lead que llego antes del periodo cerro su deal DENTRO del
    # periodo, y el embudo de ventas (cohorte) lo excluia por completo -- ver comentario de clase de
    # V2::Reports::ZohoLeadsMetrics#deals_activity.
    it 'counts deals created in the period by their current stage, regardless of the lead cohort' do
      stub_deals([
                   { 'id' => 'deal-1', 'Stage' => 'Agendo cita - Videollamada' },
                   { 'id' => 'deal-2', 'Stage' => 'Qualification' }, # visita efectiva
                   { 'id' => 'deal-3', 'Stage' => 'Closed Won' } # cuenta en ambos -- VISITA_EFECTIVA_STAGES incluye 'Closed Won'
                 ])

      expect(metrics.deals_activity).to eq(total: 3, visita_efectiva: 2, closed_won: 1)
    end
  end

  describe '#lost_count' do
    it 'is zero when there are no leads' do
      stub_leads([])

      expect(metrics.lost_count).to eq(0)
    end

    it 'counts NEW leads (Created_Time in range) with Lead_Status "Cliente perdido/Descartado" -- ' \
       'Contactado does not count, and follow-up (created before the range) does not count either' do
      stub_leads([
                   { 'Lead_Status' => 'Contactado', 'Created_Time' => '2026-08-04T10:00:00Z' },
                   { 'Lead_Status' => 'Cliente perdido/Descartado', 'Created_Time' => '2026-08-05T10:00:00Z' },
                   { 'Lead_Status' => 'Cliente perdido/Descartado', 'Created_Time' => '2026-08-06T10:00:00Z' },
                   { 'Lead_Status' => 'Cliente perdido/Descartado', 'Created_Time' => '2026-07-01T10:00:00Z' }, # seguimiento
                   { 'Lead_Status' => 'Intento de contacto', 'Created_Time' => '2026-08-06T10:00:00Z' }
                 ])

      expect(metrics.lost_count).to eq(2)
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
