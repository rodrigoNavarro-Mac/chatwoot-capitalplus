require 'rails_helper'

describe Reports::InboxBranding do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp_channel.inbox }

  it 'is valid with just an inbox' do
    branding = described_class.new(account: account, inbox: inbox)

    expect(branding).to be_valid
  end

  it 'only allows one branding record per inbox' do
    described_class.create!(account: account, inbox: inbox, accent_color: '#1f77b4')
    duplicate = described_class.new(account: account, inbox: inbox, accent_color: '#ff7f0e')

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:inbox_id]).to be_present
  end

  it 'rejects an accent_color that is not a hex color' do
    branding = described_class.new(account: account, inbox: inbox, accent_color: 'blue')

    expect(branding).not_to be_valid
    expect(branding.errors[:accent_color]).to be_present
  end

  describe 'letterhead_template' do
    it 'accepts a .docx file' do
      branding = described_class.new(account: account, inbox: inbox)
      branding.letterhead_template.attach(
        io: File.open(Rails.root.join('spec/fixtures/files/minimal_letterhead.docx')),
        filename: 'minimal_letterhead.docx',
        content_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      )

      expect(branding).to be_valid
    end

    it 'rejects a file that is not a .docx' do
      branding = described_class.new(account: account, inbox: inbox)
      branding.letterhead_template.attach(
        io: StringIO.new('not a docx'), filename: 'template.txt', content_type: 'text/plain'
      )

      expect(branding).not_to be_valid
      expect(branding.errors[:letterhead_template]).to be_present
    end

    it 'exposes the attached filename' do
      branding = described_class.new(account: account, inbox: inbox)
      branding.letterhead_template.attach(
        io: File.open(Rails.root.join('spec/fixtures/files/minimal_letterhead.docx')),
        filename: 'minimal_letterhead.docx',
        content_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      )

      expect(branding.letterhead_template_filename).to eq('minimal_letterhead.docx')
    end
  end

  describe '#accent_color_or_default' do
    it 'falls back to the default accent color when blank' do
      branding = described_class.new(account: account, inbox: inbox, accent_color: nil)

      expect(branding.accent_color_or_default).to eq(described_class::DEFAULT_ACCENT_COLOR)
    end

    it 'returns the configured accent color when present' do
      branding = described_class.new(account: account, inbox: inbox, accent_color: '#abcdef')

      expect(branding.accent_color_or_default).to eq('#abcdef')
    end
  end
end
