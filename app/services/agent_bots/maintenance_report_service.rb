require 'prawn'

class AgentBots::MaintenanceReportService
  MAX_IMAGE_WIDTH  = 400
  MAX_IMAGE_HEIGHT = 300
  JPEG_TYPES = %w[image/jpeg image/jpg].freeze
  SUPPORTED_TYPES = (JPEG_TYPES + %w[image/png]).freeze

  def initialize(conversation, config)
    @conversation = conversation
    @config = config.with_indifferent_access
  end

  def generate
    entries = Array(@conversation.custom_attributes['_collection_entries'])
    return nil if entries.empty?

    { pdf_io: generate_pdf(entries), text_summary: generate_text_summary(entries) }
  rescue StandardError => e
    Rails.logger.error("[MaintenanceReport] generate failed for conv ##{@conversation.id}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    nil
  end

  private

  def development
    @development ||= @conversation.custom_attributes['_development'].presence || '—'
  end

  def provider_name
    @provider_name ||= @conversation.contact.name
  end

  def report_date
    @report_date ||= begin
      iso = @conversation.custom_attributes['_collection_start']
      iso ? Time.parse(iso).strftime('%d/%m/%Y %H:%M') : Time.current.strftime('%d/%m/%Y %H:%M')
    end
  end

  # ── PDF generation ─────────────────────────────────────────────────────────

  def generate_pdf(entries)
    pdf = Prawn::Document.new(page_size: 'A4', margin: [40, 50, 40, 50])

    render_pdf_header(pdf)
    render_pdf_entries(pdf, entries)
    render_pdf_footer(pdf, entries)

    io = StringIO.new(pdf.render)
    io.rewind
    io
  end

  def render_pdf_header(pdf)
    pdf.font_size(18) { pdf.text('Reporte de Mantenimiento', style: :bold, align: :center) }
    pdf.move_down(8)
    pdf.font_size(11) do
      pdf.text("Desarrollo: #{development}", style: :bold)
      pdf.text("Proveedor:  #{provider_name}")
      pdf.text("Fecha:      #{report_date}")
    end
    pdf.move_down(10)
    pdf.stroke_horizontal_rule
    pdf.move_down(15)
  end

  def render_pdf_entries(pdf, entries)
    entries.each_with_index do |entry, idx|
      next if exit_entry?(entry)

      timestamp    = format_timestamp(entry['timestamp'])
      content      = entry['content'].to_s
      att_ids      = Array(entry['attachment_ids'])

      pdf.font_size(8) { pdf.text(timestamp, color: '888888') }

      pdf.font_size(11) { pdf.text(content) } if content.present?

      att_ids.each { |id| add_image_to_pdf(pdf, id) }

      pdf.move_down(10)
      unless idx == entries.size - 1
        pdf.stroke { pdf.dash(3, space: 3) { pdf.horizontal_rule } }
        pdf.move_down(10)
      end
    end
  end

  def render_pdf_footer(pdf, entries)
    pdf.stroke_horizontal_rule
    pdf.move_down(8)
    total_imgs  = entries.sum { |e| Array(e['attachment_ids']).size }
    total_texts = entries.count { |e| e['content'].present? && !exit_entry?(e) }
    pdf.font_size(9) do
      pdf.text("Total: #{total_texts} comentario(s), #{total_imgs} imagen(es)", style: :italic)
    end
  end

  def add_image_to_pdf(pdf, attachment_id)
    attachment = Attachment.find_by(id: attachment_id)
    return unless attachment&.file&.attached?

    content_type = attachment.file.content_type
    return unless SUPPORTED_TYPES.include?(content_type)

    image_data = download_as_supported(attachment, content_type)
    return unless image_data

    pdf.image StringIO.new(image_data), fit: [MAX_IMAGE_WIDTH, MAX_IMAGE_HEIGHT]
    pdf.move_down(6)
  rescue StandardError => e
    Rails.logger.warn("[MaintenanceReport] skip image #{attachment_id}: #{e.message}")
  end

  def download_as_supported(attachment, content_type)
    if JPEG_TYPES.include?(content_type)
      attachment.file.download
    else
      # Convert non-JPEG (e.g. PNG) to JPEG via image_processing variant
      variant = attachment.file.variant(format: :jpeg, resize_to_limit: [1200, 1200])
      variant.processed.download
    end
  end

  # ── Text summary ───────────────────────────────────────────────────────────

  def generate_text_summary(entries)
    lines = [
      "📋 *Reporte de Mantenimiento — #{development}*",
      "👤 Proveedor: #{provider_name}",
      "📅 #{report_date}",
      '─────────────────────'
    ]

    entries.each do |entry|
      next if exit_entry?(entry)

      ts      = format_timestamp(entry['timestamp'])
      content = entry['content'].to_s
      att_ids = Array(entry['attachment_ids'])

      lines << "[#{ts}] \"#{content}\"" if content.present?
      att_ids.each_with_index { |_, i| lines << "[#{ts}] 📷 Foto #{i + 1}" }
    end

    total_imgs  = entries.sum { |e| Array(e['attachment_ids']).size }
    total_texts = entries.count { |e| e['content'].present? && !exit_entry?(e) }

    lines << '─────────────────────'
    lines << "Total: #{total_texts} comentario(s), #{total_imgs} imagen(es)"
    lines.join("\n")
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  def exit_entry?(entry)
    entry['content'].to_s.gsub(/\s+/, '').downcase == 'salida()'
  end

  def format_timestamp(iso_string)
    return '—' if iso_string.blank?
    Time.parse(iso_string).strftime('%H:%M')
  rescue StandardError
    '—'
  end
end
