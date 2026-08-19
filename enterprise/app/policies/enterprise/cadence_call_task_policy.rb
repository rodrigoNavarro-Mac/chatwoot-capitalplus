module Enterprise::CadenceCallTaskPolicy
  include Enterprise::Concerns::CustomRolePermissible

  def index?
    custom_role_permits?('cadence_view') || custom_role_permits?('cadence_manage') || super
  end

  def complete?
    custom_role_permits?('cadence_manage') || super
  end
end
