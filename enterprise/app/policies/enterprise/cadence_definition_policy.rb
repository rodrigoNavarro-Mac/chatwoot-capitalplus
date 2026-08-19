module Enterprise::CadenceDefinitionPolicy
  include Enterprise::Concerns::CustomRolePermissible

  def index?
    custom_role_permits?('cadence_view') || custom_role_permits?('cadence_manage') || super
  end

  def create?
    custom_role_permits?('cadence_manage') || super
  end

  def update?
    custom_role_permits?('cadence_manage') || super
  end

  def destroy?
    custom_role_permits?('cadence_manage') || super
  end
end
