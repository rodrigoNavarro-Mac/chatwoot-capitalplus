class CadenceTemplateMappingPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def bulk_update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end
end
