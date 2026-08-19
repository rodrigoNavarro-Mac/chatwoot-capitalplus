class CadenceCallTaskPolicy < ApplicationPolicy
  def index?
    true
  end

  def complete?
    @account_user.administrator? || record.user_id == @user.id
  end
end

CadenceCallTaskPolicy.prepend_mod_with('CadenceCallTaskPolicy')
