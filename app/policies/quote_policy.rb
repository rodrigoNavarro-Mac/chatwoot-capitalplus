class QuotePolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def pdf?
    @account_user.administrator? || @account_user.agent?
  end
end

QuotePolicy.prepend_mod_with('QuotePolicy')
