module RevenueIntelligence
  # Todo el negocio opera desde CDMX; Zoho reporta -06:00 fijo para esta cuenta (México no
  # tiene horario de verano desde 2022). Única fuente de verdad para bucketing de fechas y
  # ventanas de sync en todo este módulo — no usar account.reporting_timezone aquí.
  TIMEZONE = 'America/Mexico_City'.freeze
end
