module Enterprise::Conversations::PermissionFilterService
  def perform
    return filter_by_permissions(permissions) if user_has_custom_role?

    super
  end

  private

  def user_has_custom_role?
    user_role == 'agent' && account_user&.custom_role_id.present?
  end

  def permissions
    account_user&.permissions || []
  end

  def filter_by_permissions(permissions)
    # Permission-based filtering with hierarchy
    # conversation_manage > conversation_unassigned_manage > conversation_participating_manage
    return role_scoped_conversations if permissions.include?('conversation_manage')

    base_scope =
      if permissions.include?('conversation_unassigned_manage')
        filter_unassigned_and_mine
      elsif permissions.include?('conversation_participating_manage')
        filter_participating_and_mine
      else
        Conversation.none
      end

    with_shared_conversations(base_scope)
  end

  # `accessible_conversations` (clase base) restringe a agentes regulares a solo lo que
  # tienen asignado (ver commit ddfc7dd1d). Los custom roles necesitan un alcance mas amplio
  # segun su permiso especifico, asi que parten de todas las conversaciones de los inboxes
  # donde el usuario es miembro, no de "accessible_conversations".
  def role_scoped_conversations
    conversations.where(inbox: user.inboxes.where(account_id: account.id))
  end

  def filter_participating_and_mine
    scoped = role_scoped_conversations
    participant_conversation_ids = ConversationParticipant.where(account_id: account.id, user_id: user.id).select(:conversation_id)

    scoped
      .where(assignee_id: user.id)
      .or(scoped.where(id: participant_conversation_ids))
  end

  def filter_unassigned_and_mine
    role_scoped_conversations.where(assignee_id: [nil, user.id])
  end

  # Un custom role sin permiso de conversaciones para todo el módulo igual puede ver
  # conversaciones puntuales que alguien le compartió manualmente (RecordShare), sin
  # importar en que inbox esten.
  def with_shared_conversations(base_scope)
    shared = conversations.where(id: shared_conversation_ids)

    Conversation.from("(#{base_scope.to_sql} UNION #{shared.to_sql}) as conversations")
                .where(account_id: account.id)
  end

  def shared_conversation_ids
    RecordShare.where(shareable_type: 'Conversation').where(
      '(shared_with_type = ? AND shared_with_id = ?) OR (shared_with_type = ? AND shared_with_id IN (?))',
      'User', user.id, 'Team', user.team_ids.presence || [0]
    ).select(:shareable_id)
  end
end
