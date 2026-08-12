require 'rails_helper'

describe Campaigns::CsvPreviewService do
  let(:account) { create(:account) }

  def file_for(content)
    StringIO.new(content)
  end

  describe '#build' do
    it 'returns valid: false when the phone column is missing' do
      file = file_for("name,email\nJohn,john@example.com\n")

      result = described_class.new(account: account, file: file).build

      expect(result[:valid]).to be(false)
      expect(result[:errors]).to include(a_string_matching(/phone_number/))
    end

    it 'returns valid: false when the file has no data rows' do
      file = file_for("phone_number,name\n")

      result = described_class.new(account: account, file: file).build

      expect(result[:valid]).to be(false)
      expect(result[:errors]).to eq(['El CSV no tiene ninguna fila de datos'])
    end

    it 'counts valid, missing-phone and duplicate rows' do
      csv = <<~CSV
        phone_number,name
        5215512345678,Ana
        ,SinTelefono
        5215512345678,AnaDuplicada
        5215587654321,Beto
      CSV
      file = file_for(csv)

      result = described_class.new(account: account, file: file).build

      expect(result).to include(
        valid: true,
        column_used: 'phone_number',
        total_rows: 4,
        valid_count: 3,
        missing_phone_count: 1,
        duplicate_count: 1
      )
    end

    it 'flags phones previously marked as invalid (bounced) for the account' do
      key = format(Redis::RedisKeys::WA_INVALID_PHONES, account_id: account.id)
      Redis::Alfred.with { |conn| conn.sadd(key, '5215512345678') }

      csv = "phone_number\n5215512345678\n5215587654321\n"
      file = file_for(csv)

      result = described_class.new(account: account, file: file).build

      expect(result[:already_bounced_count]).to eq(1)
      expect(result[:already_bounced_samples]).to eq(['5215512345678'])
    end

    it 'accepts the phone column as fallback' do
      csv = "phone\n5215512345678\n"
      file = file_for(csv)

      result = described_class.new(account: account, file: file).build

      expect(result[:column_used]).to eq('phone')
      expect(result[:valid_count]).to eq(1)
    end
  end
end
