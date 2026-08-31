# Única escritura hacia Zoho de todo el pipeline de análisis de llamadas — crea una Nota, nunca
# toca Stage/Owner/campos del Deal (regla dura del spec: el análisis no debe mover etapas ni
# cambiar ownership por sí solo). Sub-estado independiente de call_analyses.status: puede fallar y
# reintentarse sin reprocesar transcripción ni LLM.
class CallAnalysis::PublishZohoNoteJob < ApplicationJob
  queue_as :low

  def perform(call_analysis_id)
    analysis = CallAnalysis.find_by(id: call_analysis_id)
    return if analysis.blank? || !analysis.should_publish_zoho_note?

    contact = analysis.call.contact
    zoho_id, zoho_module = resolve_zoho_target(contact)

    if zoho_id.blank?
      analysis.update!(zoho_note_status: 'not_applicable')
      return
    end

    hook = analysis.account.hooks.find_by(app_id: 'zoho_crm', status: 'enabled')
    if hook.blank?
      analysis.update!(zoho_note_status: 'not_applicable')
      return
    end

    publish!(analysis, hook, zoho_id, zoho_module)
  end

  private

  def resolve_zoho_target(contact)
    ext = contact&.additional_attributes&.dig('external') || {}
    return [ext['zoho_deal_id'], 'Deals'] if ext['zoho_deal_id'].present?
    return [ext['zoho_id'], ext['zoho_module']] if ext['zoho_id'].present?

    [nil, nil]
  end

  def publish!(analysis, hook, zoho_id, zoho_module)
    builder = CallAnalysis::ZohoNoteBuilder.new(analysis)
    note = Crm::Zoho::Api::NotesClient.new(hook).create(
      zoho_id: zoho_id, zoho_module: zoho_module, title: builder.title, content: builder.content
    )
    analysis.update!(zoho_note_status: 'sent', zoho_note_id: extract_note_id(note), zoho_deal_id: zoho_id,
                     zoho_deal_stage: analysis.call.contact&.additional_attributes&.dig('external', 'zoho_deal_stage'))
  rescue StandardError => e
    analysis.update!(zoho_note_status: 'failed', zoho_note_error: e.message)
    ChatwootExceptionTracker.new(e, account: analysis.account).capture_exception
  end

  def extract_note_id(response)
    response.is_a?(Hash) ? response.dig('data', 0, 'details', 'id') : nil
  end
end
