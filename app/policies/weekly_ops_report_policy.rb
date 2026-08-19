class WeeklyOpsReportPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator?
  end

  def pdf?
    @account_user.administrator?
  end

  def create?
    @account_user.administrator?
  end
end

WeeklyOpsReportPolicy.prepend_mod_with('WeeklyOpsReportPolicy')
