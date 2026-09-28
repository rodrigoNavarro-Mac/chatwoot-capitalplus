require 'rails_helper'

RSpec.describe Quotes::CalculateAndAttachService do
  let(:account) { create(:account) }

  def payload(overrides = {})
    {
      'Deal_Name' => 'Juan Perez - Lote 12', 'Desarollo' => 'Fuego', 'Fecha_de_entrega' => '2026-01-01',
      'Plazos' => 12, 'Enganche' => 20, 'Interes' => 12, 'Superficie' => 100, 'Precio_por_m2' => 10_000,
      'Meses_sin_intereses' => 0, 'Descuento' => 0
    }.merge(overrides)
  end

  before do
    allow(Quotes::HtmlRendererService).to receive(:new).and_return(instance_double(Quotes::HtmlRendererService, render: '<html></html>'))
    allow(Quotes::PdfGeneratorService).to receive(:new).and_return(instance_double(Quotes::PdfGeneratorService, generate: 'PDF'.b))
  end

  it 'enqueues Quotes::NotifyOwnerJob only on the initial generation, not on later edits' do
    quote = create(:quote, account: account, status: 'pending')

    expect { described_class.call(quote: quote, payload: payload) }
      .to have_enqueued_job(Quotes::NotifyOwnerJob).with(quote.id).exactly(1).times

    expect { described_class.call(quote: quote.reload, payload: payload('Plazos' => 24)) }
      .not_to have_enqueued_job(Quotes::NotifyOwnerJob)
  end

  it 'does not enqueue the notification when generation fails' do
    quote = create(:quote, account: account, status: 'pending')

    expect { described_class.call(quote: quote, payload: payload('Superficie' => nil)) }
      .not_to have_enqueued_job(Quotes::NotifyOwnerJob)
    expect(quote.reload).to be_failed
  end
end
