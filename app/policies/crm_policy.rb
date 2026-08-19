class CrmPolicy < ApplicationPolicy
  def view?
    true
  end

  def manage?
    true
  end
end

CrmPolicy.prepend_mod_with('CrmPolicy')
