require 'rails_helper'

describe Reports::DocxToPdfConverterService do
  let(:docx_io) { StringIO.new('fake docx bytes') }
  let(:gotenberg_url) { ENV.fetch('GOTENBERG_URL') }

  it 'returns the PDF bytes when Gotenberg responds with 200' do
    stub_request(:post, "#{gotenberg_url}/forms/libreoffice/convert")
      .to_return(status: 200, body: '%PDF-1.4 fake pdf bytes', headers: { 'Content-Type' => 'application/pdf' })

    result = described_class.new(docx_io).convert

    expect(result).to eq('%PDF-1.4 fake pdf bytes')
  end

  it 'raises ConversionError when Gotenberg responds with a non-200 status' do
    stub_request(:post, "#{gotenberg_url}/forms/libreoffice/convert")
      .to_return(status: 500, body: 'internal error')

    expect { described_class.new(docx_io).convert }
      .to raise_error(described_class::ConversionError, /500/)
  end

  it 'raises ConversionError when Gotenberg is unreachable' do
    stub_request(:post, "#{gotenberg_url}/forms/libreoffice/convert").to_raise(Errno::ECONNREFUSED)

    expect { described_class.new(docx_io).convert }.to raise_error(described_class::ConversionError)
  end
end
