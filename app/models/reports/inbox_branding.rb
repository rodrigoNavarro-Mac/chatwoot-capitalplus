# == Schema Information
#
# Table name: reports_inbox_brandings
#
#  id           :bigint           not null, primary key
#  accent_color :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  inbox_id     :bigint           not null
#
# Indexes
#
#  index_reports_inbox_brandings_on_account_id  (account_id)
#  index_reports_inbox_brandings_on_inbox_id    (inbox_id) UNIQUE
#
# Personalización visual (color de acento + logo) usada por Reports::WeeklyOpsReportPdfService al
# armar el PDF exportable del reporte semanal operativo. Un registro por inbox — cada inbox
# representa un desarrollo, y agregar un desarrollo nuevo no debe requerir tocar código.
class Reports::InboxBranding < ApplicationRecord
  include Rails.application.routes.url_helpers

  self.table_name = 'reports_inbox_brandings'

  ALLOWED_LOGO_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  MAX_LOGO_SIZE = 2.megabytes
  ALLOWED_LETTERHEAD_CONTENT_TYPES = %w[application/vnd.openxmlformats-officedocument.wordprocessingml.document].freeze
  MAX_LETTERHEAD_SIZE = 5.megabytes
  DEFAULT_ACCENT_COLOR = '#1f77b4'.freeze

  belongs_to :account
  belongs_to :inbox

  has_one_attached :logo
  # .docx con el membrete del desarrollo (header/footer/márgenes ya diseñados en Word). Cuando
  # está presente, Reports::WeeklyOpsReportPdfService delega en Reports::WeeklyOpsReportDocxService
  # + Reports::DocxToPdfConverterService (Gotenberg) en vez de dibujar el PDF con Prawn.
  has_one_attached :letterhead_template

  validates :inbox_id, uniqueness: true
  validates :accent_color, format: { with: /\A#[0-9A-Fa-f]{6}\z/ }, allow_blank: true
  validate :acceptable_logo, if: -> { logo.changed? }
  validate :acceptable_letterhead_template, if: -> { letterhead_template.changed? }

  def accent_color_or_default
    accent_color.presence || DEFAULT_ACCENT_COLOR
  end

  def logo_url
    return '' unless logo.attached?

    url_for(logo)
  end

  def letterhead_template_filename
    letterhead_template.attached? ? letterhead_template.filename.to_s : ''
  end

  private

  def acceptable_logo
    return unless logo.attached?

    errors.add(:logo, 'is too big') if logo.byte_size > MAX_LOGO_SIZE
    errors.add(:logo, 'filetype not supported') unless ALLOWED_LOGO_CONTENT_TYPES.include?(logo.content_type)
  end

  def acceptable_letterhead_template
    return unless letterhead_template.attached?

    errors.add(:letterhead_template, 'is too big') if letterhead_template.byte_size > MAX_LETTERHEAD_SIZE
    return if ALLOWED_LETTERHEAD_CONTENT_TYPES.include?(letterhead_template.content_type)

    errors.add(:letterhead_template, 'filetype not supported')
  end
end
