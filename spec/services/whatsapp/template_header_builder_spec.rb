require 'rails_helper'

describe Whatsapp::TemplateHeaderBuilder do
  subject(:builder) { described_class.new }

  describe '#call' do
    it 'returns nil when header is blank' do
      expect(builder.call(nil)).to be_nil
      expect(builder.call({})).to be_nil
    end

    it 'returns nil for type none' do
      expect(builder.call({ 'type' => 'NONE' })).to be_nil
    end

    it 'builds a text header parameter' do
      result = builder.call({ 'type' => 'Text', 'text' => 'Rodrigo' })

      expect(result).to eq({ type: 'header', parameters: [{ type: 'text', text: 'Rodrigo' }] })
    end

    it 'omits the parameter for a static text header without a variable' do
      expect(builder.call({ 'type' => 'text' })).to be_nil
    end

    it 'builds an image header from a link' do
      result = builder.call({ 'type' => 'image', 'link' => 'https://dominio.com/imagen.png' })

      expect(result).to eq({ type: 'header', parameters: [{ type: 'image', image: { link: 'https://dominio.com/imagen.png' } }] })
    end

    it 'builds an image header from a media id' do
      result = builder.call({ 'type' => 'image', 'id' => 'META_MEDIA_ID' })

      expect(result).to eq({ type: 'header', parameters: [{ type: 'image', image: { id: 'META_MEDIA_ID' } }] })
    end

    it 'rejects an image header with both link and id' do
      expect { builder.call({ 'type' => 'image', 'link' => 'https://dominio.com/a.png', 'id' => 'X' }) }
        .to raise_error(Whatsapp::TemplateValidationError)
    end

    it 'rejects an image header with neither link nor id' do
      expect { builder.call({ 'type' => 'image' }) }.to raise_error(Whatsapp::TemplateValidationError)
    end

    it 'builds a video header from a link' do
      result = builder.call({ 'type' => 'video', 'link' => 'https://dominio.com/video.mp4' })

      expect(result).to eq({ type: 'header', parameters: [{ type: 'video', video: { link: 'https://dominio.com/video.mp4' } }] })
    end

    it 'builds a document header with a filename' do
      result = builder.call({ 'type' => 'document', 'link' => 'https://dominio.com/Brochure.pdf', 'filename' => 'Brochure.pdf' })

      expect(result).to eq({
                             type: 'header',
                             parameters: [{ type: 'document', document: { link: 'https://dominio.com/Brochure.pdf', filename: 'Brochure.pdf' } }]
                           })
    end

    it 'builds a document header without a filename, omitting the key entirely' do
      result = builder.call({ 'type' => 'document', 'link' => 'https://dominio.com/Brochure.pdf' })

      expect(result[:parameters].first[:document]).to eq({ link: 'https://dominio.com/Brochure.pdf' })
      expect(result[:parameters].first[:document]).not_to have_key(:filename)
    end

    it 'builds a document header from a media id with filename' do
      result = builder.call({ 'type' => 'document', 'id' => 'META_MEDIA_ID', 'filename' => 'Brochure.pdf' })

      expect(result).to eq({
                             type: 'header',
                             parameters: [{ type: 'document', document: { id: 'META_MEDIA_ID', filename: 'Brochure.pdf' } }]
                           })
    end

    it 'rejects a self-hosted media link that is not https' do
      expect { builder.call({ 'type' => 'document', 'link' => 'http://dominio.com/Brochure.pdf' }) }
        .to raise_error(Whatsapp::TemplateValidationError)
    end

    it 'builds a location header with all fields' do
      result = builder.call({
                              'type' => 'location', 'latitude' => 19.0414, 'longitude' => -98.2063,
                              'name' => 'Oficina Capital Plus', 'address' => 'Puebla, México'
                            })

      expect(result).to eq({
                             type: 'header',
                             parameters: [{
                               type: 'location',
                               location: { latitude: 19.0414, longitude: -98.2063, name: 'Oficina Capital Plus', address: 'Puebla, México' }
                             }]
                           })
    end

    it 'builds a location header without optional name/address' do
      result = builder.call({ 'type' => 'location', 'latitude' => 19.0414, 'longitude' => -98.2063 })

      expect(result[:parameters].first[:location]).to eq({ latitude: 19.0414, longitude: -98.2063 })
    end

    it 'rejects a location header missing latitude' do
      expect { builder.call({ 'type' => 'location', 'longitude' => -98.2063 }) }.to raise_error(Whatsapp::TemplateValidationError)
    end

    it 'rejects a location header missing longitude' do
      expect { builder.call({ 'type' => 'location', 'latitude' => 19.0414 }) }.to raise_error(Whatsapp::TemplateValidationError)
    end

    it 'rejects an unknown header type' do
      expect { builder.call({ 'type' => 'carousel' }) }.to raise_error(Whatsapp::TemplateValidationError)
    end
  end
end
