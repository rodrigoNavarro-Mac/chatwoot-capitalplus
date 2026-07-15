require 'rails_helper'

describe CadenceDefinition do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:whatsapp_inbox) { whatsapp_channel.inbox }

  it 'is valid with just a name' do
    definition = described_class.new(account: account, inbox: whatsapp_inbox, name: 'Cadencia A')
    expect(definition).to be_valid
  end

  it 'only allows one is_default: true per inbox' do
    described_class.create!(account: account, inbox: whatsapp_inbox, name: 'Default', is_default: true)
    duplicate = described_class.new(account: account, inbox: whatsapp_inbox, name: 'Otro default', is_default: true)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:is_default]).to be_present
  end

  it 'allows several definitions with the same segment_value (for A/B testing)' do
    described_class.create!(account: account, inbox: whatsapp_inbox, name: 'A', segment_value: 'Inversión')
    variant_b = described_class.new(account: account, inbox: whatsapp_inbox, name: 'B', segment_value: 'Inversión')

    expect(variant_b).to be_valid
  end

  describe '#mark_as_default!' do
    it 'unmarks the previous default and marks this one, atomically' do
      old_default = described_class.create!(account: account, inbox: whatsapp_inbox, name: 'Old default', is_default: true)
      new_default = described_class.create!(account: account, inbox: whatsapp_inbox, name: 'New default')

      new_default.mark_as_default!

      expect(old_default.reload.is_default).to be(false)
      expect(new_default.reload.is_default).to be(true)
    end
  end

  describe 'dependent destroy' do
    it 'destroys its step definitions when the cadence definition is destroyed' do
      definition = described_class.create!(account: account, inbox: whatsapp_inbox, name: 'A')
      CadenceStepDefinition.create!(
        cadence_definition: definition, position: 1, template_key: 'wa_x', template_name: 'x',
        schedule_type: 'immediate', wait_window_minutes: 15
      )

      expect { definition.destroy! }.to change(CadenceStepDefinition, :count).by(-1)
    end
  end
end
