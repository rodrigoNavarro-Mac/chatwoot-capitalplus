require 'rails_helper'

describe Quotes::HtmlRendererService do
  def quote_for(desarrollo)
    Quote.new(
      desarrollo: desarrollo, lote: 'L-12', superficie: 200, precio_m2: 5000, monto: 1_000_000,
      enganche_pct: 10, enganche_monto: 100_000, plazos: 1, precio_total: 1_000_000,
      schedule: [{ 'periodo' => 1, 'fecha' => '2026-12-01', 'pago' => 900_000 }]
    )
  end

  it 'uses the Amura template for Amura quotes regardless of case' do
    html = described_class.new(quote_for(' AMURA ')).render

    expect(html).to include('cobranza@amura.mx', 'alt="Amura"')
    expect(html).not_to include('fuegocancun')
  end

  it 'falls back to the default template for other developments' do
    html = described_class.new(quote_for('Fuego')).render

    expect(html).to include('cobranza@fuegocancun.com')
    expect(html).not_to include('amura.mx')
  end
end
