class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  # include_unassigned: true permite que un agente regular actue tambien sobre conversaciones
  # sin dueno (ej. tomarlas via Bulk Actions), sin darle acceso a lo asignado a otros agentes.
  # No afecta a custom roles (el modulo enterprise define su propia logica de permisos).
  def initialize(conversations, user, account, include_unassigned: false)
    @conversations = conversations
    @user = user
    @account = account
    @include_unassigned = include_unassigned
  end

  def perform
    return conversations if user_role == 'administrator'

    accessible_conversations
  end

  private

  def accessible_conversations
    return own_or_unassigned_within_member_inboxes if @include_unassigned

    conversations.where(assignee_id: user.id)
  end

  # Las conversaciones sin dueno solo son accesibles si el agente es miembro del inbox
  # (misma restriccion que ya aplica al listado normal via ConversationFinder), para no
  # dar acceso a conversaciones de inboxes ajenos solo por estar sin asignar.
  def own_or_unassigned_within_member_inboxes
    conversations.where(assignee_id: user.id)
                 .or(conversations.where(assignee_id: nil, inbox_id: member_inbox_ids))
  end

  def member_inbox_ids
    user.inboxes.where(account_id: account.id).select(:id)
  end

  def account_user
    AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
