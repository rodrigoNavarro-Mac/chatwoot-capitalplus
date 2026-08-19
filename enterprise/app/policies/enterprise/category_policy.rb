module Enterprise::CategoryPolicy
  include Enterprise::Concerns::CustomRolePermissible

  def index?
    return super unless custom_role_present?

    custom_role_permits?('knowledge_base_view') || custom_role_permits?('knowledge_base_manage')
  end

  def show?
    return super unless custom_role_present?

    custom_role_permits?('knowledge_base_view') || custom_role_permits?('knowledge_base_manage')
  end

  def update?
    custom_role_permits?('knowledge_base_manage') || super
  end

  def edit?
    custom_role_permits?('knowledge_base_manage') || super
  end

  def create?
    custom_role_permits?('knowledge_base_manage') || super
  end

  def destroy?
    custom_role_permits?('knowledge_base_manage') || super
  end

  def reorder?
    custom_role_permits?('knowledge_base_manage') || super
  end

  private

  def custom_role_present?
    @account_user&.custom_role_id.present?
  end
end
