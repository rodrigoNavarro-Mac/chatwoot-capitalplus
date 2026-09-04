# Aplana CallAnalysis (jsonb: qualification_map/scorecard/metrics/objections/risks) a
# revenue_call_features — una fila 1:1 por call_id, para que Fase 3 (agregados) no tenga que
# parsear jsonb en cada corrida. Solo lectura sobre call_analyses/calls; nunca los modifica.
class RevenueIntelligence::ExtractCallFeaturesJob < ApplicationJob
  queue_as :scheduled_jobs

  QUALIFICATION_KEYS = CallAnalysis::StructuredAnalysisLlmService::QUALIFICATION_KEYS

  def perform(account_id = nil)
    hooks = Integrations::Hook.enabled.where(app_id: 'zoho_crm')
    hooks = hooks.where(account_id: account_id) if account_id

    hooks.find_each do |hook|
      build_for_account(hook.account)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::ExtractCallFeaturesJob] account=#{hook.account_id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: hook.account).capture_exception
    end
  end

  private

  def build_for_account(account)
    cursor_service = RevenueIntelligence::SyncCursorService.new(account, 'call_features')
    since = cursor_service.since
    until_at = Time.current
    contacts = revenue_contact_lookup(account)

    analyses(account, since, until_at).find_each do |analysis|
      upsert_feature(account, analysis, contacts)
    rescue StandardError => e
      Rails.logger.error("[RevenueIntelligence::ExtractCallFeaturesJob] call_analysis=#{analysis.id} error=#{e.message}")
      ChatwootExceptionTracker.new(e, account: account).capture_exception
    end

    cursor_service.advance!(until_at)
  rescue StandardError => e
    cursor_service&.record_error!(e.message)
    raise
  end

  def analyses(account, since, until_at)
    scope = CallAnalysis.where(account_id: account.id, status: 'completed')
    since ? scope.where(updated_at: since...until_at) : scope.where(updated_at: ..until_at)
  end

  def revenue_contact_lookup(account)
    account.revenue_contacts.where.not(chatwoot_contact_id: nil).pluck(:chatwoot_contact_id, :id).to_h
  end

  def upsert_feature(account, analysis, contacts)
    call = account.calls.find_by(id: analysis.call_id)
    return if call.blank?

    feature = account.revenue_call_features.find_or_initialize_by(call_id: analysis.call_id)
    feature.assign_attributes(feature_attrs(analysis, call, contacts))
    feature.save!
  end

  def feature_attrs(analysis, call, contacts)
    identity_attrs(analysis, call, contacts)
      .merge(classification_attrs(analysis))
      .merge(scorecard_attrs(analysis))
      .merge(metric_attrs(analysis))
      .merge(qualification_attrs(analysis))
  end

  def identity_attrs(analysis, call, contacts)
    {
      call_analysis_id: analysis.id, revenue_contact_id: contacts[call.contact_id], zoho_deal_id: analysis.zoho_deal_id,
      agent_id: analysis.agent_id, started_at: call.started_at
    }
  end

  def classification_attrs(analysis)
    {
      role: analysis.role, conversation_type: analysis.conversation_type, intent_level: analysis.intent_level,
      confidence: analysis.confidence, outcome_type: analysis.outcome_type, outcome_at: analysis.outcome_at
    }
  end

  def scorecard_attrs(analysis)
    { score_total: analysis.total_score, score_reading: analysis.score_reading }
  end

  def metric_attrs(analysis)
    metrics = analysis.metrics.is_a?(Hash) ? analysis.metrics : {}
    {
      talk_ratio: metrics['talk_ratio'], longest_monologue_seconds: metrics['longest_monologue_seconds'],
      open_questions: metrics.dig('questions', 'open') || 0, closed_questions: metrics.dig('questions', 'closed') || 0,
      cta_used: metrics['cta_used'] == true, objection_count: Array(analysis.objections).size, risk_count: Array(analysis.risks).size
    }
  end

  def qualification_attrs(analysis)
    map = analysis.qualification_map.is_a?(Hash) ? analysis.qualification_map : {}
    captured = QUALIFICATION_KEYS.index_with { |key| map.dig(key, 'captured') == true }
    captured_count = captured.count { |_key, value| value }

    captured.transform_keys { |key| :"qual_#{key}" }
            .merge(qualification_count: captured_count, qualification_completeness: (captured_count / QUALIFICATION_KEYS.size.to_f).round(4))
  end
end
