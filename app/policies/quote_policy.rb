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

  def amortization_pdf?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    @account_user.administrator? || @account_user.agent?
  end

  def update?
    @account_user.administrator? || @account_user.agent?
  end

  # El controller además exige status: 'failed' — solo se puede borrar un intento fallido, nunca
  # una cotización completada (es un registro financiero).
  def destroy?
    @account_user.administrator? || @account_user.agent?
  end

  def products?
    @account_user.administrator? || @account_user.agent?
  end

  def developments?
    @account_user.administrator? || @account_user.agent?
  end

  # Mismo grupo que ya puede editar descuento/interés/meses sin intereses (ver
  # Api::V1::Accounts::QuotesController#can_manage_sensitive_fields?) — autorizar un plazo largo
  # es una decisión del mismo nivel que esas.
  # El método de la acción se llama `authorize_quote` (no `authorize`) para no chocar con el
  # helper `authorize` de Pundit que ya usa este mismo controller.
  def authorize_quote?
    @account_user.administrator? || @account_user.custom_role&.permissions&.include?('quote_sensitive_fields_manage')
  end
end

QuotePolicy.prepend_mod_with('QuotePolicy')
