module Enterprise::CrmPolicy
  include Enterprise::Concerns::CustomRolePermissible

  def view?
    return super unless custom_role_present?

    custom_role_permits?('crm_view') || custom_role_permits?('crm_manage')
  end

  def manage?
    return super unless custom_role_present?

    custom_role_permits?('crm_manage')
  end

  private

  def custom_role_present?
    @account_user&.custom_role_id.present?
  end
end
