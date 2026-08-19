module Enterprise::WeeklyOpsReportPolicy
  include Enterprise::Concerns::CustomRolePermissible

  def index?
    custom_role_permits?('weekly_ops_report_view') || custom_role_permits?('weekly_ops_report_manage') || super
  end

  def show?
    custom_role_permits?('weekly_ops_report_view') || custom_role_permits?('weekly_ops_report_manage') || super
  end

  def pdf?
    custom_role_permits?('weekly_ops_report_view') || custom_role_permits?('weekly_ops_report_manage') || super
  end

  def create?
    custom_role_permits?('weekly_ops_report_manage') || super
  end
end
