require 'rails_helper'

describe RevenueIntelligence::LeadMapper do
  describe '.map' do
    let(:payload) do
      {
        'Owner' => { 'id' => 'owner-1', 'name' => 'Ana Setter' },
        'Desarrollo' => 'Fuego',
        'Created_Time' => '2026-01-05T10:00:00-06:00',
        'First_Contact_Time' => '2026-01-05T10:05:00-06:00',
        'Fecha_de_calificaci_n' => '2026-01-06T09:00:00-06:00',
        'Lead_Status' => 'Contactado',
        'Raz_n_de_descarte' => nil,
        'Raz_n_de_compra' => 'Inversión',
        'Tiempo_de_inversi_n' => '6 meses',
        'G_nero' => 'Femenino',
        'Ocupaci_n' => 'Empresaria',
        'Estado_civil' => 'Casada',
        'Etapa_de_vida' => 'Familia joven',
        'Nacionalidad' => 'Mexicana',
        'Rango_de_edad' => '30-40',
        'Presupuesto' => '1.5 millones',
        'Lead_Source' => 'Facebook',
        'Campa_a' => { 'id' => 'camp-1', 'name' => 'Campaña lookup' },
        'Campaing_Name' => 'Campaña Q1',
        'Ad_Account_Id' => 'act-1', 'Ad_Account_Name' => 'Cuenta 1',
        'Adset_Id' => 'adset-1', 'Adset_Name' => 'Adset 1',
        'Advert_Id' => 'ad-1', 'Advert_name' => 'Anuncio 1',
        'Form_Id' => 'form-1', 'Form_Name' => 'Formulario 1',
        'Plataforma' => 'Meta',
        'Contador_Intentos' => 3,
        'Numero_Reasignaciones' => 1
      }
    end
    let(:attrs) { described_class.map(payload) }

    it 'maps identity and desarrollo' do
      expect(attrs[:owner_id]).to eq('owner-1')
      expect(attrs[:owner_name]).to eq('Ana Setter')
      expect(attrs[:desarrollo]).to eq('Fuego')
    end

    it 'maps qualification fields' do
      expect(attrs[:created_at_source]).to eq(Time.zone.parse('2026-01-05T10:00:00-06:00'))
      expect(attrs[:lead_status]).to eq('Contactado')
      expect(attrs[:razon_compra]).to eq('Inversión')
    end

    it 'parses presupuesto while keeping the raw value' do
      expect(attrs[:presupuesto_raw]).to eq('1.5 millones')
      expect(attrs[:presupuesto_min]).to eq(1_500_000.0)
      expect(attrs[:presupuesto_max]).to eq(1_500_000.0)
    end

    it 'maps campaign identity fields' do
      expect(attrs[:campaign_id]).to eq('camp-1')
      expect(attrs[:campaign_name]).to eq('Campaña Q1')
    end

    it 'maps the Meta Ads funnel fields' do
      expect(attrs[:ad_account_id]).to eq('act-1')
      expect(attrs[:adset_name]).to eq('Adset 1')
      expect(attrs[:advert_name]).to eq('Anuncio 1')
      expect(attrs[:platform]).to eq('Meta')
    end

    it 'maps traceability counters and preserves the raw payload' do
      expect(attrs[:attempt_count]).to eq(3)
      expect(attrs[:reassignment_count]).to eq(1)
      expect(attrs[:raw_payload]).to eq(payload)
    end
  end

  describe '.map edge cases' do
    it 'falls back to the Campa_a lookup name when Campaing_Name is blank' do
      attrs = described_class.map({ 'Campa_a' => { 'id' => 'camp-1', 'name' => 'Nombre del lookup' } })

      expect(attrs[:campaign_name]).to eq('Nombre del lookup')
    end

    it 'defaults attempt_count and reassignment_count to 0 when absent' do
      attrs = described_class.map({})

      expect(attrs[:attempt_count]).to eq(0)
      expect(attrs[:reassignment_count]).to eq(0)
    end

    it 'handles a nil payload without raising' do
      attrs = described_class.map(nil)

      expect(attrs[:owner_id]).to be_nil
      expect(attrs[:presupuesto_raw]).to be_nil
    end

    it 'leaves created_at_source nil for an unparseable date instead of raising' do
      attrs = described_class.map({ 'Created_Time' => 'not-a-date' })

      expect(attrs[:created_at_source]).to be_nil
    end
  end
end
