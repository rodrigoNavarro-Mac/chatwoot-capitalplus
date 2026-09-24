require 'rails_helper'

RSpec.describe Quotes::CalculatorService do
  def payload(overrides = {})
    {
      'Deal_Name' => 'Juan Perez - Lote 12',
      'Owner' => { 'id' => '1', 'email' => 'owner@example.com' },
      'Desarollo' => 'Fuego',
      'Fecha_de_entrega' => '2026-01-01',
      'Plazos' => 12,
      'Enganche' => 20,
      'Interes' => 12,
      'Superficie' => 100,
      'Precio_por_m2' => 10_000,
      'Meses_sin_intereses' => 0,
      'Descuento' => 0
    }.merge(overrides)
  end

  it 'parses nombre/lote from Deal_Name' do
    result = described_class.calculate(payload)
    expect(result[:nombre]).to eq('Juan Perez')
    expect(result[:lote]).to eq('Lote 12')
  end

  it 'raises when a required field is missing' do
    expect { described_class.calculate(payload('Superficie' => nil)) }
      .to raise_error(Quotes::CalculatorService::ValidationError, /Superficie/)
  end

  it 'raises when financing fields are missing for a financed deal' do
    expect { described_class.calculate(payload('Enganche' => nil)) }
      .to raise_error(Quotes::CalculatorService::ValidationError, /Enganche/)
  end

  describe 'contado (Plazos = 0)' do
    it 'produces a single schedule row equal to the discounted amount' do
      result = described_class.calculate(payload('Plazos' => 0, 'Enganche' => nil, 'Interes' => nil, 'Descuento' => 10))

      expect(result[:monto_base]).to eq(1_000_000)
      expect(result[:descuento_aplicado]).to eq(100_000)
      expect(result[:monto]).to eq(900_000)
      expect(result[:schedule].size).to eq(1)
      expect(result[:schedule].first[:pago]).to eq(900_000)
      expect(result[:schedule].first[:saldo_final]).to eq(0)
      expect(result[:precio_total]).to eq(900_000)
    end
  end

  describe 'financiamiento' do
    it 'builds a full amortization schedule that closes at zero' do
      result = described_class.calculate(payload)

      expect(result[:schedule].size).to eq(12)
      expect(result[:schedule].last[:saldo_final]).to eq(0)
      expect(result[:enganche_monto]).to eq(200_000)
      expect(result[:precio_total]).to eq(result[:enganche_monto] + result[:schedule].sum { |r| r[:pago] })
      # French amortization sanity check: capital installments must sum back to the financed amount (pv)
      pv = result[:monto] - result[:enganche_monto]
      expect(result[:schedule].sum { |r| r[:capital] }).to eq(pv)
    end

    it 'applies a fixed-amount discount when Descuento > 100' do
      result = described_class.calculate(payload('Descuento' => 50_000))
      expect(result[:descuento_aplicado]).to eq(50_000)
      expect(result[:monto]).to eq(950_000)
    end

    it 'keeps installments equal to pago_mensual with zero interest during MSI months' do
      result = described_class.calculate(payload('Meses_sin_intereses' => 3))

      result[:schedule].first(3).each do |row|
        expect(row[:interes]).to eq(0)
        expect(row[:capital]).to eq(result[:pago_mensual])
      end
      expect(result[:schedule][3][:interes]).to be > 0
    end

    it 'still amortizes correctly when Interes is 0 (0% financing) with MSI shorter than the term' do
      result = described_class.calculate(payload('Interes' => 0, 'Meses_sin_intereses' => 3))

      pv = result[:monto] - result[:enganche_monto]
      # con 0% de interes en todo el plazo, el pago mensual debe ser simplemente pv / meses_sin_intereses
      # (la fórmula de amortización cae al fallback de "factor > 0" en vez de pv/plazos)
      expect(result[:pago_mensual]).to eq((pv / 3).round(2))
      expect(result[:schedule].sum { |r| r[:interes] }).to eq(0)
      expect(result[:schedule].last[:saldo_final]).to eq(0)
    end

    it 'normalizes Enganche/Interes given as fractions (<=1)' do
      result = described_class.calculate(payload('Enganche' => 0.2, 'Interes' => 0.12))
      expect(result[:enganche_pct]).to eq(20)
      expect(result[:interes_pct]).to eq(12)
    end
  end
end
