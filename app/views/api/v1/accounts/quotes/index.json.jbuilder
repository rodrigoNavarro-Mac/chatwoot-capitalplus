json.array! @quotes do |quote|
  json.id quote.id
  json.contact_id quote.contact_id
  json.zoho_deal_id quote.zoho_deal_id
  json.trigger_source quote.trigger_source
  json.status quote.status
  json.error_message quote.error_message
  json.nombre quote.nombre
  json.lote quote.lote
  json.desarrollo quote.desarrollo
  json.plazos quote.plazos
  json.precio_total quote.precio_total
  json.pdf_attached quote.pdf.attached?
  json.created_at quote.created_at
end
