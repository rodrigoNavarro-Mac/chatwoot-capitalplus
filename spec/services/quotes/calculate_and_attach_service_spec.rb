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

  context 'when the development rule requires authorization for this term' do
    before do
      create(:quote_development_rule, account: account, desarrollo: 'Fuego', quote_development_rule_tiers_attributes: [
               { hasta_meses: 12, msi: false, requires_authorization: false },
               { hasta_meses: nil, msi: false, requires_authorization: true }
             ])
    end

    it 'does not notify the owner on initial generation while authorization is pending' do
      quote = create(:quote, account: account, status: 'pending')

      expect { described_class.call(quote: quote, payload: payload('Plazos' => 24)) }
        .not_to have_enqueued_job(Quotes::NotifyOwnerJob)
      expect(quote.reload).to be_authorization_status_pending
    end

    it 'notifies the owner once an edit brings the term back under the automatic threshold' do
      quote = create(:quote, account: account, status: 'pending')
      described_class.call(quote: quote, payload: payload('Plazos' => 24))
      expect(quote.reload).to be_authorization_status_pending

      expect { described_class.call(quote: quote.reload, payload: payload('Plazos' => 6)) }
        .to have_enqueued_job(Quotes::NotifyOwnerJob).with(quote.id).exactly(1).times
      expect(quote.reload).to be_authorization_status_not_required
    end

    it 'does not re-notify when an edit keeps an already-deliverable quote deliverable' do
      quote = create(:quote, account: account, status: 'pending')
      described_class.call(quote: quote, payload: payload('Plazos' => 6))
      expect(quote.reload).to be_authorization_status_not_required

      expect { described_class.call(quote: quote.reload, payload: payload('Plazos' => 8)) }
        .not_to have_enqueued_job(Quotes::NotifyOwnerJob)
    end
  end
end
