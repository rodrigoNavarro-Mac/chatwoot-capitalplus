class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  # include_unassigned: true permite que un agente regular actue tambien sobre conversaciones
  # sin dueno (ej. tomarlas via Bulk Actions), sin darle acceso a lo asignado a otros agentes.
  # No afecta a custom roles (el modulo enterprise define su propia logica de permisos).
  #
  # plan_hint_selective_filter: viene de Chatwoot upstream (CW-7787) para evitar que el
  # planner de Postgres escanee por inbox cuando hay un filtro muy selectivo (ej. labels)
  # en cuentas grandes. Ver hinted_accessible_conversations.
  def initialize(conversations, user, account, include_unassigned: false, plan_hint_selective_filter: false)
    @conversations = conversations
    @user = user
    @account = account
    @include_unassigned = include_unassigned
    @plan_hint_selective_filter = plan_hint_selective_filter
  end

  def perform
    return conversations if user_role == 'administrator'

    accessible_conversations
  end

  private

  def accessible_conversations
    return own_or_unassigned_within_member_inboxes if @include_unassigned
    return hinted_accessible_conversations if @plan_hint_selective_filter

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

  # Mismas filas que la rama por defecto (assignee_id: user.id). Chatwoot upstream aplica
  # el hint `inbox_id + 0` (CW-7787) a un chequeo de membresia de inbox porque su default
  # filtra por inbox; CapitalPlus filtra por asignacion (ver comentario en initialize), asi
  # que aqui el hint no cambia el resultado, solo evita que el planner intente usarlo para
  # decidir un plan distinto cuando coexiste con un filtro muy selectivo (ej. labels).
  def hinted_accessible_conversations
    conversations.where(
      '(conversations.inbox_id + 0) IS NOT NULL AND conversations.assignee_id = :user_id',
      user_id: user.id
    )
  end

  def account_user
    AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
