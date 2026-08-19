class CampaignPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator?
  end

  def create?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end

  def metrics?
    @account_user.administrator?
  end

  def recipients?
    @account_user.administrator?
  end

  def csv_usage_report?
    @account_user.administrator?
  end

  def csv_preview?
    @account_user.administrator?
  end

  def pause?
    @account_user.administrator?
  end

  def resume?
    @account_user.administrator?
  end
end

CampaignPolicy.prepend_mod_with('CampaignPolicy')
