# Genera la respuesta CSV de un reporte -- extraído de Api::V2::Accounts::ReportsController
# (donde vivía como método privado) para que Api::V1::Accounts::WeeklyOpsReportsController#leads_export
# lo reuse sin duplicar el fix del BOM.
module CsvExportHelper
  extend ActiveSupport::Concern

  # BOM (\xEF\xBB\xBF) al inicio: sin él, Excel en Windows reinterpreta el UTF-8 como
  # Windows-1252 y corrompe cualquier acento/emoji (confirmado en producción, 2026-09-15).
  def generate_csv(filename, template)
    response.headers['Content-Type'] = 'text/csv; charset=utf-8'
    response.headers['Content-Disposition'] = "attachment; filename=#{filename}.csv"
    csv_body = render_to_string(layout: false, template: template, formats: [:csv])
    render body: "\xEF\xBB\xBF#{csv_body}"
  end
end
