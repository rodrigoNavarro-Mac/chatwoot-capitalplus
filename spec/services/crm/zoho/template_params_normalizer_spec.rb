require 'rails_helper'

describe Crm::Zoho::TemplateParamsNormalizer do
  describe '#normalize' do
    it 'returns no header, empty body_params and button_params when nothing is sent' do
      result = described_class.new({}).normalize

      expect(result).to eq(header: nil, body_params: [], button_params: [])
    end

    it 'prefers the new header object and lowercases its type' do
      result = described_class.new({ header: { type: 'DOCUMENT', link: 'https://x.com/a.pdf' } }).normalize

      expect(result[:header]).to eq({ 'type' => 'document', 'link' => 'https://x.com/a.pdf' })
    end

    it 'normalizes header_image_url into a new-style header' do
      result = described_class.new({ header_image_url: 'https://dominio.com/fuego.png' }).normalize

      expect(result[:header]).to eq({ 'type' => 'image', 'link' => 'https://dominio.com/fuego.png' })
    end

    it 'normalizes header_document_url and header_document_filename into a new-style header' do
      result = described_class.new({
                                     header_document_url: 'https://mdb3blnhtc41axtd.public.blob.vercel-storage.com/Brochure_FUEGO_julio14_2026.pdf',
                                     header_document_filename: 'Brochure_FUEGO_julio14_2026.pdf'
                                   }).normalize

      expect(result[:header]).to eq({
                                      'type' => 'document',
                                      'link' => 'https://mdb3blnhtc41axtd.public.blob.vercel-storage.com/Brochure_FUEGO_julio14_2026.pdf',
                                      'filename' => 'Brochure_FUEGO_julio14_2026.pdf'
                                    })
    end

    it 'normalizes header_text into a new-style header' do
      result = described_class.new({ header_text: 'Rodrigo' }).normalize

      expect(result[:header]).to eq({ 'type' => 'text', 'text' => 'Rodrigo' })
    end

    it 'normalizes header_location into a new-style header' do
      result = described_class.new({ header_location: { latitude: 19.0414, longitude: -98.2063 } }).normalize

      expect(result[:header]).to eq({ 'type' => 'location', 'latitude' => 19.0414, 'longitude' => -98.2063 })
    end

    it 'passes body_params and button_params through untouched' do
      result = described_class.new({ body_params: ['Rodrigo'], button_params: [{ type: 'url', index: 0 }] }).normalize

      expect(result[:body_params]).to eq(['Rodrigo'])
      expect(result[:button_params]).to eq([{ 'type' => 'url', 'index' => 0 }])
    end

    it 'rejects two legacy header fields sent simultaneously' do
      params = { header_image_url: 'https://a.com/a.png', header_document_url: 'https://a.com/a.pdf' }

      expect { described_class.new(params).normalize }.to raise_error(Whatsapp::TemplateValidationError)
    end

    it 'rejects the new header object combined with a legacy header field' do
      params = { header: { type: 'text', text: 'hi' }, header_image_url: 'https://a.com/a.png' }

      expect { described_class.new(params).normalize }.to raise_error(Whatsapp::TemplateValidationError)
    end
  end
end
