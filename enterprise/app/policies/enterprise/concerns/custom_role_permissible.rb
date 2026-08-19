module Enterprise::Concerns::CustomRolePermissible
  private

  def custom_role_permits?(permission)
    @account_user&.custom_role&.permissions&.include?(permission) || false
  end
end
