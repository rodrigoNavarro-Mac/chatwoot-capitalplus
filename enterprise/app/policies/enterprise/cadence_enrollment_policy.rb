module Enterprise::CadenceEnrollmentPolicy
  include Enterprise::Concerns::CustomRolePermissible

  def index?
    custom_role_permits?('cadence_view') || custom_role_permits?('cadence_manage') || super
  end

  def show?
    return true if custom_role_permits?('cadence_manage')
    return own_or_team_record? if custom_role_permits?('cadence_view')

    super
  end

  def eligible_conversations?
    custom_role_permits?('cadence_view') || custom_role_permits?('cadence_manage') || super
  end

  def create?
    custom_role_permits?('cadence_manage') || super
  end

  def enroll_past_leads?
    custom_role_permits?('cadence_manage') || super
  end

  def retry_failed?
    custom_role_permits?('cadence_manage') || super
  end

  def pause?
    custom_role_permits?('cadence_manage') || super
  end

  def resume?
    custom_role_permits?('cadence_manage') || super
  end

  def cancel?
    custom_role_permits?('cadence_manage') || super
  end

  private

  def own_or_team_record?
    return true if record.assignee_id == user.id

    team_ids = user.teams.where(account_id: account&.id).pluck(:id)
    team_ids.include?(record.conversation&.team_id)
  end
end
