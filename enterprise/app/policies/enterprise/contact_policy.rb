module Enterprise::ContactPolicy
  include Enterprise::Concerns::CustomRolePermissible

  def show?
    return super unless custom_role_present?

    custom_role_permits?('contact_view') || custom_role_permits?('contact_manage') || shared_with_user?
  end

  def create?
    return super unless custom_role_present?

    custom_role_permits?('contact_manage')
  end

  def update?
    return super unless custom_role_present?

    custom_role_permits?('contact_manage')
  end

  def export?
    custom_role_permits?('contact_manage') || super
  end

  def import?
    custom_role_permits?('contact_manage') || super
  end

  def destroy?
    custom_role_permits?('contact_manage') || super
  end

  private

  def custom_role_present?
    @account_user&.custom_role_id.present?
  end

  def shared_with_user?
    record.record_shares.exists?(shared_with_type: 'User', shared_with_id: user.id) ||
      record.record_shares.exists?(shared_with_type: 'Team', shared_with_id: user.team_ids)
  end
end
