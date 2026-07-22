class CadenceEnrollmentPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def create?
    @account_user.administrator?
  end

  def eligible_conversations?
    @account_user.administrator?
  end

  def enroll_past_leads?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator?
  end

  def pause?
    @account_user.administrator?
  end

  def resume?
    @account_user.administrator?
  end

  def cancel?
    @account_user.administrator?
  end
end
