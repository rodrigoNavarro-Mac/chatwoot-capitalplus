require 'rails_helper'

describe RevenueIntelligence::DealMapper do
  describe '.map' do
    let(:payload) do
      {
        'Owner' => { 'id' => 'owner-1', 'name' => 'Carlos Asesor' },
        'Desarollo' => 'Fuego', # typo real de Zoho, una sola erre
        'Stage' => 'Qualification',
        'Pipeline' => 'Standard',
        'Probability' => 40,
        'Amount' => 1_500_000,
        'Expected_Revenue' => 600_000,
        'Lead_Source' => 'Facebook',
        'Campaign_Source' => { 'id' => 'camp-1', 'name' => 'Campaña Q1' },
        'Created_Time' => '2026-01-05T10:00:00-06:00',
        'Stage_Modified_Time' => '2026-01-10T10:00:00-06:00',
        'Closing_Date' => '2026-02-01',
        'Reason_For_Loss__s' => nil
      }
    end
    let(:attrs) { described_class.map(payload) }

    it 'maps identity fields' do
      expect(attrs[:owner_id]).to eq('owner-1')
      expect(attrs[:desarrollo]).to eq('Fuego')
    end

    it 'maps pipeline fields' do
      expect(attrs[:stage]).to eq('Qualification')
      expect(attrs[:pipeline]).to eq('Standard')
      expect(attrs[:amount]).to eq(1_500_000)
      expect(attrs[:campaign_source]).to eq('Campaña Q1')
    end

    it 'maps dates' do
      expect(attrs[:created_at_source]).to eq(Time.zone.parse('2026-01-05T10:00:00-06:00'))
      expect(attrs[:stage_modified_at]).to eq(Time.zone.parse('2026-01-10T10:00:00-06:00'))
      expect(attrs[:closing_date]).to eq(Date.parse('2026-02-01'))
    end

    it 'defaults won/lost to false and preserves the raw payload' do
      expect(attrs[:won]).to be(false)
      expect(attrs[:lost]).to be(false)
      expect(attrs[:raw_payload]).to eq(payload)
    end

    it 'sets won=true only for the exact "Cerrado ganado" stage' do
      expect(described_class.map({ 'Stage' => 'Cerrado ganado' })[:won]).to be(true)
      expect(described_class.map({ 'Stage' => 'Apartado' })[:won]).to be(false)
    end

    it 'sets lost=true only for the exact "Cerrado perdido" stage' do
      expect(described_class.map({ 'Stage' => 'Cerrado perdido' })[:lost]).to be(true)
      expect(described_class.map({ 'Stage' => 'Agendo cita - Videollamada' })[:lost]).to be(false)
    end

    it 'preserves quote fields verbatim in quote_fields without building analytics on them' do
      payload = {
        'Precio_por_m2' => 25_000, 'Superficie' => 80, 'Descuento' => 5,
        'Enganche' => 10, 'Plazos' => 60, 'Fecha_de_entrega' => '2027-01-01'
      }

      attrs = described_class.map(payload)

      expect(attrs[:quote_fields]).to eq(
        'Precio_por_m2' => 25_000, 'Superficie' => 80, 'Descuento' => 5,
        'Enganche' => 10, 'Plazos' => 60, 'Fecha_de_entrega' => '2027-01-01'
      )
    end

    it 'omits absent quote fields instead of storing them as nil' do
      attrs = described_class.map({ 'Precio_por_m2' => 25_000 })

      expect(attrs[:quote_fields]).to eq('Precio_por_m2' => 25_000)
    end

    it 'falls back to Campaign_Source as a plain string when it is not a lookup hash' do
      attrs = described_class.map({ 'Campaign_Source' => 'Facebook Ads' })

      expect(attrs[:campaign_source]).to eq('Facebook Ads')
    end

    it 'handles a nil payload without raising' do
      attrs = described_class.map(nil)

      expect(attrs[:stage]).to be_nil
      expect(attrs[:won]).to be(false)
    end
  end
end
