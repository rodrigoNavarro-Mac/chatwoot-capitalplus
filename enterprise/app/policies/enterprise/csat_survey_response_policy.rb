module Enterprise::CsatSurveyResponsePolicy
  include Enterprise::Concerns::CustomRolePermissible

  def index?
    custom_role_permits?('report_view') || custom_role_permits?('report_manage') || super
  end

  def metrics?
    custom_role_permits?('report_view') || custom_role_permits?('report_manage') || super
  end

  def download?
    custom_role_permits?('report_manage') || super
  end

  def update?
    @account_user.administrator? || custom_role_permits?('report_manage')
  end
end
