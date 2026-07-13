class Api::V1::Accounts::Cadences::TemplateMappingsController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action :check_authorization

  def index
    @entries = build_entries
  end

  def bulk_update
    ActiveRecord::Base.transaction do
      permitted_mappings.each { |mapping| upsert_mapping!(mapping) }
    end
    @entries = build_entries
    render :index
  end

  def destroy
    @inbox.cadence_template_mappings.where(template_key: params[:template_key]).destroy_all
    head :no_content
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def check_authorization
    authorize(CadenceTemplateMapping)
  end

  def overrides
    @overrides ||= @inbox.cadence_template_mappings.index_by(&:template_key)
  end

  def build_entries
    Cadences::StepDefinitions::STEPS.map do |step|
      key = step[:template_key]
      override = overrides[key]
      default = Cadences::TemplateResolver.mappings.dig('default', key) || {}

      {
        step: step[:step],
        template_key: key,
        name: override&.name || default['name'],
        language: override&.language || default['language'],
        namespace: override&.namespace || default['namespace'],
        is_custom: override.present?
      }
    end
  end

  def upsert_mapping!(mapping)
    record = @inbox.cadence_template_mappings.find_or_initialize_by(template_key: mapping[:template_key])
    record.account_id = Current.account.id
    record.assign_attributes(mapping.slice(:name, :language, :namespace))
    record.save!
  end

  def permitted_mappings
    params.require(:mappings).map { |mapping| mapping.permit(:template_key, :name, :language, :namespace) }
  end
end
