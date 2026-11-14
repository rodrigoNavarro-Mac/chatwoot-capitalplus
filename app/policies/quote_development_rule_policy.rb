# Administradores, o agentes con el permiso custom 'quote_sensitive_fields_manage' — el mismo grupo
# que ya puede editar descuento/interés/MSI en una cotización y aprobar cotizaciones pendientes
# (ver QuotePolicy#authorize_quote?), así que configurar la tasa por defecto y los tramos de cada
# desarrollo es una decisión del mismo nivel.
class QuoteDevelopmentRulePolicy < ApplicationPolicy
  def index?
    can_manage_quote_rules?
  end

  def create?
    can_manage_quote_rules?
  end

  def update?
    can_manage_quote_rules?
  end

  def destroy?
    can_manage_quote_rules?
  end

  private

  def can_manage_quote_rules?
    @account_user.administrator? || @account_user.custom_role&.permissions&.include?('quote_sensitive_fields_manage')
  end
end

QuoteDevelopmentRulePolicy.prepend_mod_with('QuoteDevelopmentRulePolicy')
