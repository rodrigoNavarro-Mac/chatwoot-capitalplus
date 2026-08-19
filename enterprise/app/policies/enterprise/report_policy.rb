module Enterprise::ReportPolicy
  include Enterprise::Concerns::CustomRolePermissible

  def view?
    custom_role_permits?('report_view') || custom_role_permits?('report_manage') || super
  end
end
