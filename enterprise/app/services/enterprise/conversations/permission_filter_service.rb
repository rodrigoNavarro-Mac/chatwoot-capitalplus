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
    return accessible_conversations if permissions.include?('conversation_manage')

    base_scope =
      if permissions.include?('conversation_unassigned_manage')
        filter_unassigned_and_mine
      elsif permissions.include?('conversation_participating_manage')
        accessible_conversations.assigned_to(user)
      else
        Conversation.none
      end

    with_shared_conversations(base_scope)
  end

  def filter_unassigned_and_mine
    mine = accessible_conversations.assigned_to(user)
    unassigned = accessible_conversations.unassigned

    Conversation.from("(#{mine.to_sql} UNION #{unassigned.to_sql}) as conversations")
                .where(account_id: account.id)
  end

  # Un custom role sin permiso de conversaciones para todo el módulo igual puede ver
  # conversaciones puntuales que alguien le compartió manualmente (RecordShare).
  def with_shared_conversations(base_scope)
    shared = accessible_conversations.where(id: shared_conversation_ids)

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
