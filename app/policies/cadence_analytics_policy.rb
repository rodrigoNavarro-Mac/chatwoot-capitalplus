class CadenceAnalyticsPolicy < ApplicationPolicy
  def summary?
    @account_user.administrator?
  end

  def steps?
    @account_user.administrator?
  end

  def agents?
    @account_user.administrator?
  end

  def templates?
    @account_user.administrator?
  end

  def variants?
    @account_user.administrator?
  end
end

CadenceAnalyticsPolicy.prepend_mod_with('CadenceAnalyticsPolicy')
