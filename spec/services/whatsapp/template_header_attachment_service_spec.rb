require 'rails_helper'

describe Whatsapp::TemplateHeaderAttachmentService do
  let(:account) { create(:account) }
  let(:message) { create(:message, account: account) }

  describe '#call' do
    it 'creates an image attachment pointing at the external url' do
      described_class.new(message: message, media_url: 'https://cdn.example.com/photo.jpg', media_type: 'image').call

      attachment = message.attachments.last
      expect(attachment.file_type).to eq('image')
      expect(attachment.external_url).to eq('https://cdn.example.com/photo.jpg')
      expect(attachment.account_id).to eq(account.id)
    end

    it 'maps a document media_type to the :file attachment type' do
      described_class.new(message: message, media_url: 'https://cdn.example.com/brochure.pdf', media_type: 'document').call

      expect(message.attachments.last.file_type).to eq('file')
    end

    it 'does nothing when media_url is blank' do
      expect { described_class.new(message: message, media_url: nil, media_type: 'image').call }
        .not_to(change { message.attachments.count })
    end

    it 'does nothing when media_type is unknown' do
      expect { described_class.new(message: message, media_url: 'https://cdn.example.com/x', media_type: 'carousel').call }
        .not_to(change { message.attachments.count })
    end
  end
end
