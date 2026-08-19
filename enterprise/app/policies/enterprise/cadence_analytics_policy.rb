module Enterprise::CadenceAnalyticsPolicy
  include Enterprise::Concerns::CustomRolePermissible

  def summary?
    custom_role_permits?('cadence_view') || custom_role_permits?('cadence_manage') || super
  end

  def steps?
    custom_role_permits?('cadence_view') || custom_role_permits?('cadence_manage') || super
  end

  def agents?
    custom_role_permits?('cadence_view') || custom_role_permits?('cadence_manage') || super
  end

  def templates?
    custom_role_permits?('cadence_view') || custom_role_permits?('cadence_manage') || super
  end

  def variants?
    custom_role_permits?('cadence_view') || custom_role_permits?('cadence_manage') || super
  end
end
