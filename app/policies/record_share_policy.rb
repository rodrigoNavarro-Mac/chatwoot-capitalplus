class RecordSharePolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    administrator? || shareable_accessible?
  end

  def destroy?
    administrator? || record.shared_by_id == user.id || shareable_accessible?
  end

  private

  def administrator?
    @account_user&.administrator?
  end

  # Cualquiera que ya pueda ver la conversación/contacto puede extender esa visibilidad
  # compartiéndolo con otro usuario o equipo.
  def shareable_accessible?
    shareable = record.shareable
    return false unless shareable

    Pundit.policy!(user_context, shareable).show?
  end
end

RecordSharePolicy.prepend_mod_with('RecordSharePolicy')
