# Acceso al mini-análisis de IA por card (Reports::WeeklyOpsAnalysisLlmService::CARD_KEYS),
# compartido entre Reports::WeeklyOpsReportPdfService y Reports::WeeklyOpsReportDocxService — cada
# uno decide cómo renderizarlo (Prawn vs OOXML), pero ambos necesitan lo mismo: el texto (si existe)
# para una key dada.
module Reports::ReportCardAnalyses
  # Cards que ya muestran su mini-análisis en la sección de tablas (tienen tabla/línea Y gráfica) —
  # la sección de gráficas no lo repite para esas, solo para las que son gráfica únicamente. Mismo
  # criterio que WeeklyOpsReport.vue: la nota aparece una sola vez, junto a la primera
  # representación de la card en el documento.
  DUAL_REPRESENTATION_CARD_KEYS = %w[conversion_totals quality_by_source].freeze

  def card_analysis(key)
    return nil if key.blank?

    (report.card_analyses || {})[key.to_s].presence
  end
end
