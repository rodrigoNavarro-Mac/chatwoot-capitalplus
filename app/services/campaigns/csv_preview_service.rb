class Campaigns::CsvPreviewService
  REQUIRED_PHONE_COLUMNS = %w[phone_number phone].freeze
  SAMPLE_LIMIT = 10

  pattr_initialize [:account!, :file!]

  def build
    rows = parse_csv_rows
    return { valid: false, errors: parse_errors } if parse_errors.present?
    return { valid: false, errors: ['El CSV no tiene ninguna fila de datos'] } if rows.empty?

    phone_column = REQUIRED_PHONE_COLUMNS.find { |col| rows.first.key?(col) }
    return { valid: false, errors: ["No se encontró la columna 'phone_number' o 'phone' en el CSV"] } unless phone_column

    analyze(rows, phone_column)
  end

  private

  def parse_errors
    @parse_errors ||= []
  end

  def parse_csv_rows
    raw = file.read
    raw = raw.dup.force_encoding('BINARY') if raw.frozen?
    raw.sub!(/\A\xEF\xBB\xBF/n, '')
    raw.force_encoding('UTF-8')
    raw = raw.encode('UTF-8', 'UTF-8', invalid: :replace, undef: :replace, replace: '') unless raw.valid_encoding?

    CSV.parse(raw, headers: true).map(&:to_h)
  rescue StandardError => e
    parse_errors << "No se pudo leer el CSV: #{e.message}"
    []
  end

  def analyze(rows, phone_column)
    stats = { missing_phone_count: 0, already_bounced_count: 0, missing_samples: [], bounced_samples: [] }
    seen_phones = Hash.new(0)
    invalid_phones = load_invalid_phones

    rows.each { |row| tally_row(row, phone_column, seen_phones, invalid_phones, stats) }

    build_result(rows, phone_column, seen_phones, stats)
  end

  def tally_row(row, phone_column, seen_phones, invalid_phones, stats)
    phone = row[phone_column].presence

    if phone.blank?
      stats[:missing_phone_count] += 1
      stats[:missing_samples] << row if stats[:missing_samples].size < SAMPLE_LIMIT
      return
    end

    seen_phones[phone] += 1
    return unless invalid_phones.include?(phone)

    stats[:already_bounced_count] += 1
    stats[:bounced_samples] << phone if stats[:bounced_samples].size < SAMPLE_LIMIT
  end

  def build_result(rows, phone_column, seen_phones, stats)
    duplicate_count = seen_phones.values.sum { |count| count > 1 ? count - 1 : 0 }

    {
      valid: true,
      column_used: phone_column,
      total_rows: rows.size,
      valid_count: rows.size - stats[:missing_phone_count],
      missing_phone_count: stats[:missing_phone_count],
      duplicate_count: duplicate_count,
      already_bounced_count: stats[:already_bounced_count],
      missing_phone_samples: stats[:missing_samples].map { |r| r['name'].presence || r.values.first },
      already_bounced_samples: stats[:bounced_samples]
    }
  end

  def load_invalid_phones
    key = format(Redis::RedisKeys::WA_INVALID_PHONES, account_id: account.id)
    Redis::Alfred.with { |conn| conn.smembers(key) }.to_set
  rescue StandardError
    Set.new
  end
end
