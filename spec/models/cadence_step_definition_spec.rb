require 'rails_helper'

describe CadenceStepDefinition do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:cadence_definition) do
    CadenceDefinition.create!(account: account, inbox: whatsapp_inbox, name: 'Cadencia de prueba')
  end

  def base_attrs(overrides = {})
    {
      cadence_definition: cadence_definition,
      position: 1,
      template_key: 'wa_primer_contacto',
      template_name: 'cadencia_primer_contacto',
      template_language: 'es_MX',
      schedule_type: 'immediate',
      wait_window_minutes: 15
    }.merge(overrides)
  end

  it 'is valid with the minimum required attributes' do
    expect(described_class.new(base_attrs)).to be_valid
  end

  it 'requires a unique position per cadence_definition' do
    described_class.create!(base_attrs)
    duplicate = described_class.new(base_attrs(template_key: 'wa_segundo_intento'))

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:position]).to be_present
  end

  it 'requires a unique template_key per cadence_definition' do
    described_class.create!(base_attrs)
    duplicate = described_class.new(base_attrs(position: 2))

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:template_key]).to be_present
  end

  it 'requires offset_minutes when schedule_type is offset_from_last_step' do
    record = described_class.new(base_attrs(schedule_type: 'offset_from_last_step', offset_minutes: nil))

    expect(record).not_to be_valid
    expect(record.errors[:offset_minutes]).to be_present
  end

  it 'is valid with offset_minutes when schedule_type is offset_from_last_step' do
    record = described_class.new(base_attrs(schedule_type: 'offset_from_last_step', offset_minutes: 300))

    expect(record).to be_valid
  end

  it 'requires day_offset and time_of_day when schedule_type is day_offset_at_time' do
    record = described_class.new(base_attrs(schedule_type: 'day_offset_at_time', day_offset: nil, time_of_day: nil))

    expect(record).not_to be_valid
    expect(record.errors[:day_offset]).to be_present
    expect(record.errors[:time_of_day]).to be_present
  end

  it 'rejects a malformed time_of_day' do
    record = described_class.new(base_attrs(schedule_type: 'day_offset_at_time', day_offset: 1, time_of_day: '9am'))

    expect(record).not_to be_valid
    expect(record.errors[:time_of_day]).to be_present
  end

  it 'requires media_type when media_url is present' do
    record = described_class.new(base_attrs(media_url: 'https://cdn.example.com/video.mp4', media_type: nil))

    expect(record).not_to be_valid
    expect(record.errors[:media_type]).to be_present
  end

  it 'requires media_name when media_type is document' do
    record = described_class.new(base_attrs(media_url: 'https://cdn.example.com/doc.pdf', media_type: 'document', media_name: nil))

    expect(record).not_to be_valid
    expect(record.errors[:media_name]).to be_present
  end

  it 'is valid with a video media attachment and no media_name' do
    record = described_class.new(base_attrs(media_url: 'https://cdn.example.com/video.mp4', media_type: 'video'))

    expect(record).to be_valid
  end

  describe '#to_snapshot' do
    it 'includes the fields the cadence engine needs, and nothing else' do
      record = described_class.create!(base_attrs(media_url: 'https://cdn.example.com/v.mp4', media_type: 'video'))

      snapshot = record.to_snapshot

      expect(snapshot).to include(
        'position' => 1, 'template_key' => 'wa_primer_contacto', 'schedule_type' => 'immediate',
        'wait_window_minutes' => 15, 'media_url' => 'https://cdn.example.com/v.mp4', 'media_type' => 'video'
      )
      expect(snapshot).not_to have_key('cadence_definition_id')
    end

    it 'includes the body_variables mapping' do
      record = described_class.create!(base_attrs(body_variables: { '1' => '{{ contact.name }}' }))

      expect(record.to_snapshot).to include('body_variables' => { '1' => '{{ contact.name }}' })
    end
  end

  it 'defaults body_variables to an empty hash' do
    expect(described_class.new(base_attrs).body_variables).to eq({})
  end

  describe '.ordered' do
    it 'returns steps sorted by position' do
      described_class.create!(base_attrs(position: 2, template_key: 'wa_segundo_intento'))
      described_class.create!(base_attrs(position: 1))

      expect(cadence_definition.cadence_step_definitions.ordered.pluck(:position)).to eq([1, 2])
    end
  end
end
