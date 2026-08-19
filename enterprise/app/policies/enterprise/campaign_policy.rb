module Enterprise::CampaignPolicy
  include Enterprise::Concerns::CustomRolePermissible

  def index?
    custom_role_permits?('campaign_view') || custom_role_permits?('campaign_manage') || super
  end

  def show?
    custom_role_permits?('campaign_view') || custom_role_permits?('campaign_manage') || super
  end

  def metrics?
    custom_role_permits?('campaign_view') || custom_role_permits?('campaign_manage') || super
  end

  def recipients?
    custom_role_permits?('campaign_view') || custom_role_permits?('campaign_manage') || super
  end

  def csv_usage_report?
    custom_role_permits?('campaign_view') || custom_role_permits?('campaign_manage') || super
  end

  def csv_preview?
    custom_role_permits?('campaign_view') || custom_role_permits?('campaign_manage') || super
  end

  def create?
    custom_role_permits?('campaign_manage') || super
  end

  def update?
    custom_role_permits?('campaign_manage') || super
  end

  def destroy?
    custom_role_permits?('campaign_manage') || super
  end

  def pause?
    custom_role_permits?('campaign_manage') || super
  end

  def resume?
    custom_role_permits?('campaign_manage') || super
  end
end
