require 'rails_helper'

describe ConversationFinder do
  subject(:conversation_finder) { described_class.new(user_1, params) }

  let!(:account) { create(:account) }
  let!(:user_1) { create(:user, account: account) }
  let!(:user_2) { create(:user, account: account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let!(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: 'testing_source_id') }
  let!(:restricted_inbox) { create(:inbox, account: account) }

  before do
    create(:inbox_member, user: user_1, inbox: inbox)
    create(:inbox_member, user: user_2, inbox: inbox)
    create(:conversation, account: account, inbox: inbox, assignee: user_1)
    create(:conversation, account: account, inbox: inbox, assignee: user_1)
    create(:conversation, account: account, inbox: inbox, assignee: user_1, status: 'resolved')
    create(:conversation, account: account, inbox: inbox, assignee: user_2, contact_inbox: contact_inbox)
    # unassigned conversation
    create(:conversation, account: account, inbox: inbox)
    Current.account = account
  end

  describe '#perform' do
    context 'with status' do
      let(:params) { { status: 'open', assignee_type: 'me' } }

      it 'filter conversations by status' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 2
      end
    end

    context 'with inbox' do
      let!(:restricted_conversation) { create(:conversation, account: account, inbox_id: restricted_inbox.id) }

      it 'returns conversation from any inbox if its admin' do
        params = { inbox_id: restricted_inbox.id }
        result = described_class.new(admin, params).perform

        expect(result[:conversations].map(&:id)).to include(restricted_conversation.id)
      end

      it 'does not return an unassigned conversation from inbox even if agent is its member' do
        params = { inbox_id: restricted_inbox.id }
        create(:inbox_member, user: user_1, inbox: restricted_inbox)
        result = described_class.new(user_1, params).perform

        expect(result[:conversations].map(&:id)).not_to include(restricted_conversation.id)
      end

      it 'returns conversation from inbox if it is assigned to the agent' do
        params = { inbox_id: restricted_inbox.id }
        create(:inbox_member, user: user_1, inbox: restricted_inbox)
        restricted_conversation.update!(assignee: user_1)
        result = described_class.new(user_1, params).perform

        expect(result[:conversations].map(&:id)).to include(restricted_conversation.id)
      end

      it 'does not return conversations from inboxes where agent is not a member' do
        params = { inbox_id: restricted_inbox.id }
        result = described_class.new(user_1, params).perform

        expect(result[:conversations].map(&:id)).not_to include(restricted_conversation.id)
      end

      it 'returns only the conversations from the inbox if inbox_id filter is passed' do
        conversation = create(:conversation, account: account, inbox_id: inbox.id)
        params = { inbox_id: restricted_inbox.id }
        result = described_class.new(admin, params).perform

        conversation_ids = result[:conversations].map(&:id)
        expect(conversation_ids).not_to include(conversation.id)
        expect(conversation_ids).to include(restricted_conversation.id)
      end
    end

    context 'with assignee_type all' do
      let(:params) { { assignee_type: 'all' } }

      it 'filter conversations by assignee type all, restricted to the agents own conversations' do
        # Los agentes solo ven lo que tienen asignado (ver Conversations::PermissionFilterService),
        # asi que "all" para un agente equivale a sus propias conversaciones abiertas.
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 2
      end
    end

    context 'with assignee_type unassigned' do
      let(:params) { { assignee_type: 'unassigned' } }
      let!(:agent_bot_conversation) do
        create(:conversation, account: account, inbox: inbox, assignee_agent_bot: create(:agent_bot, account: account))
      end

      it 'never returns unassigned conversations to a regular agent' do
        # Los agentes no ven conversaciones sin dueno; solo lo que les esta asignado.
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 0
        expect(result[:conversations]).not_to include(agent_bot_conversation)
      end
    end

    context 'with status all' do
      let(:params) { { status: 'all' } }

      it 'returns all of the agents own conversations regardless of status' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 3
      end
    end

    context 'with unread sort' do
      let(:params) { { status: 'open', sort_by: 'unread' } }

      it 'returns all conversations matching the selected status with the highest unread count first' do
        most_unread_conversation = create(:conversation, account: account, inbox: inbox, assignee: user_1,
                                                         agent_last_seen_at: 1.hour.ago)
        unread_conversation = create(:conversation, account: account, inbox: inbox, assignee: user_1,
                                                    agent_last_seen_at: 1.hour.ago)
        read_conversation = create(:conversation, account: account, inbox: inbox, assignee: user_1,
                                                  agent_last_seen_at: 1.minute.from_now)
        resolved_unread_conversation = create(:conversation, account: account, inbox: inbox, status: 'resolved', assignee: user_1,
                                                             agent_last_seen_at: 1.hour.ago)

        [most_unread_conversation, unread_conversation, read_conversation, resolved_unread_conversation].each do |conversation|
          create(:message, account: account, inbox: inbox, conversation: conversation,
                           message_type: :incoming, created_at: 5.minutes.ago)
        end
        create(:message, account: account, inbox: inbox, conversation: most_unread_conversation,
                         message_type: :incoming, created_at: 4.minutes.ago)
        resolved_unread_conversation.update!(status: 'resolved')
        read_conversation.update!(last_activity_at: 1.minute.from_now)
        unread_conversation.update!(last_activity_at: 2.minutes.from_now)

        result = conversation_finder.perform
        conversation_ids = result[:conversations].map(&:id)

        expect(conversation_ids).to include(most_unread_conversation.id, unread_conversation.id, read_conversation.id)
        expect(conversation_ids).not_to include(resolved_unread_conversation.id)
        expect(conversation_ids.index(most_unread_conversation.id)).to be < conversation_ids.index(unread_conversation.id)
        expect(conversation_ids.index(unread_conversation.id)).to be < conversation_ids.index(read_conversation.id)
      end

      it 'includes private incoming messages in unread counts used for ordering' do
        private_unread_conversation = create(:conversation, account: account, inbox: inbox, assignee: user_1,
                                                            agent_last_seen_at: 1.hour.ago)
        unread_conversation = create(:conversation, account: account, inbox: inbox, assignee: user_1,
                                                    agent_last_seen_at: 1.hour.ago)
        read_conversation = create(:conversation, account: account, inbox: inbox, assignee: user_1,
                                                  agent_last_seen_at: 1.minute.from_now)

        2.times do
          create(:message, account: account, inbox: inbox, conversation: private_unread_conversation,
                           message_type: :incoming, private: true, created_at: 5.minutes.ago)
        end
        create(:message, account: account, inbox: inbox, conversation: unread_conversation,
                         message_type: :incoming, created_at: 5.minutes.ago)
        create(:message, account: account, inbox: inbox, conversation: read_conversation,
                         message_type: :incoming, created_at: 5.minutes.ago)
        private_unread_conversation.update!(last_activity_at: 10.minutes.ago)
        unread_conversation.update!(last_activity_at: 2.minutes.from_now)
        read_conversation.update!(last_activity_at: 1.minute.from_now)

        result = conversation_finder.perform
        conversation_ids = result[:conversations].map(&:id)

        expect(private_unread_conversation.unread_incoming_messages.count).to eq 2
        expect(conversation_ids.index(private_unread_conversation.id)).to be < conversation_ids.index(unread_conversation.id)
        expect(conversation_ids.index(unread_conversation.id)).to be < conversation_ids.index(read_conversation.id)
      end
    end

    context 'with assignee_type assigned' do
      let(:params) { { assignee_type: 'assigned' } }
      let!(:agent_bot_conversation) do
        create(:conversation, account: account, inbox: inbox, assignee_agent_bot: create(:agent_bot, account: account))
      end

      it 'filter conversations by assignee type assigned' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 2
        expect(result[:conversations]).not_to include(agent_bot_conversation)
      end

      it 'returns the correct meta, scoped to the agents own conversations' do
        result = conversation_finder.perform
        expect(result[:count]).to eq({
                                       mine_count: 2,
                                       assigned_count: 2,
                                       unassigned_count: 0,
                                       all_count: 2
                                     })
      end
    end

    context 'with team' do
      let(:team) { create(:team, account: account) }
      let(:params) { { team_id: team.id } }

      it 'filter conversations by team' do
        # el assignee debe ser miembro del team, si no AssignmentHandler#ensure_assignee_is_from_team
        # limpia el assignee_id al guardar (ver app/models/concerns/assignment_handler.rb).
        create(:team_member, team: team, user: user_1)
        create(:conversation, account: account, inbox: inbox, assignee: user_1, team: team)
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 1
      end
    end

    context 'with labels' do
      let(:params) { { labels: ['resolved'] } }

      it 'filter conversations by labels' do
        conversation = inbox.conversations.first
        conversation.update_labels('resolved')

        result = conversation_finder.perform
        expect(result[:conversations].length).to be 1
      end
    end

    context 'with source_id' do
      let(:own_contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: 'own_testing_source_id') }
      let(:params) { { source_id: 'own_testing_source_id' } }

      before do
        create(:conversation, account: account, inbox: inbox, assignee: user_1, contact_inbox: own_contact_inbox)
      end

      it 'filter conversations by source id' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 1
      end
    end

    context 'without source' do
      let(:params) { {} }

      it 'returns the agents own conversations regardless of source' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 2
      end
    end

    context 'with updated_within' do
      # assignee_type 'unassigned' solo tiene sentido para un administrador: un agente
      # regular nunca ve conversaciones sin dueno (Conversations::PermissionFilterService).
      let(:conversation_finder) { described_class.new(admin, params) }
      let(:params) { { updated_within: 20, assignee_type: 'unassigned', sort_by: 'created_at_asc' } }

      it 'filters based on params, sort order but returns all conversations without pagination with in time range' do
        # value of updated_within is in seconds
        # write spec based on that
        conversations = create_list(:conversation, 50, account: account,
                                                       inbox: inbox, assignee: nil,
                                                       updated_at: Time.now.utc - 30.seconds,
                                                       created_at: Time.now.utc - 30.seconds)
        # update updated_at of 27 conversations to be with in 20 seconds
        conversations[0..27].each do |conversation|
          conversation.update(updated_at: Time.now.utc - 10.seconds)
        end
        result = conversation_finder.perform
        # pagination is not applied
        # filters are applied
        # modified conversations + 1 conversation created during set up
        expect(result[:conversations].length).to be 29
        # ensure that the conversations are sorted by created_at
        expect(result[:conversations].first.created_at).to be < result[:conversations].last.created_at
      end
    end

    context 'with pagination' do
      let(:params) { { status: 'open', assignee_type: 'me', page: 1 } }

      it 'returns paginated conversations' do
        create_list(:conversation, 50, account: account, inbox: inbox, assignee: user_1)
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 25
      end
    end

    context 'with perform_meta_only' do
      let(:params) { { assignee_type: 'assigned' } }

      it 'returns only count without conversations' do
        result = conversation_finder.perform_meta_only
        expect(result).to have_key(:count)
        expect(result).not_to have_key(:conversations)
      end

      it 'returns the correct counts' do
        result = conversation_finder.perform_meta_only
        expect(result[:count]).to eq({
                                       mine_count: 2,
                                       assigned_count: 2,
                                       unassigned_count: 0,
                                       all_count: 2
                                     })
      end

      it 'returns same counts as perform' do
        meta_result = conversation_finder.perform_meta_only
        full_result = conversation_finder.perform
        expect(meta_result[:count]).to eq(full_result[:count])
      end
    end

    context 'with unattended' do
      let(:params) { { status: 'open', assignee_type: 'me', conversation_type: 'unattended' } }

      it 'returns unattended conversations' do
        # Conversation#ensure_waiting_since (before_create) siempre pone waiting_since a
        # created_at al crear, sin importar el valor pasado. En produccion, waiting_since
        # solo se limpia cuando llega una respuesta real (Message#set_first_reply_created_at
        # hace conversation.update(first_reply_created_at:, waiting_since: nil) al mismo
        # tiempo) — asi que replicamos eso con un update posterior en vez de pasarlo al create,
        # que el callback ignoraria.
        attended_conversation = create(:conversation, account: account, assignee: user_1)
        attended_conversation.update!(first_reply_created_at: Time.now.utc, waiting_since: nil)
        create(:conversation, account: account, first_reply_created_at: nil, assignee: user_1) # unattended_conversation_no_first_reply
        create(:conversation, account: account, first_reply_created_at: Time.now.utc,
                              assignee: user_1, waiting_since: Time.now.utc) # unattended_conversation_waiting_since

        result = conversation_finder.perform
        # conv1 y conv2 del fixture compartido (arriba) tambien cuentan: nunca recibieron una
        # primera respuesta real, asi que legitimamente siguen "sin atender".
        expect(result[:conversations].length).to be 4
      end
    end

    context 'with whatsapp_window_open' do
      let!(:whatsapp_channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
      let(:params) { { status: 'open', assignee_type: 'me', conversation_type: 'whatsapp_window_open' } }

      it 'returns only whatsapp conversations with an unexpired window' do
        create(:conversation, account: account, inbox: whatsapp_channel.inbox, assignee: user_1,
                              whatsapp_window_expires_at: 1.hour.from_now) # open_window_conversation
        create(:conversation, account: account, inbox: whatsapp_channel.inbox, assignee: user_1,
                              whatsapp_window_expires_at: 1.hour.ago) # expired_window_conversation
        create(:conversation, account: account, inbox: inbox, assignee: user_1,
                              whatsapp_window_expires_at: 1.hour.from_now) # non_whatsapp_inbox_conversation

        result = conversation_finder.perform
        expect(result[:conversations].length).to be 1
      end
    end

    context 'with participating' do
      let(:params) { { status: 'open', assignee_type: 'all', conversation_type: 'participating' } }

      it 'excludes participating conversations from inboxes the user no longer has access to' do
        accessible_conversation = create(:conversation, account: account, inbox: inbox)
        revoked_conversation = create(:conversation, account: account, inbox: restricted_inbox)
        revoked_membership = create(:inbox_member, user: user_1, inbox: restricted_inbox)
        create(:conversation_participant, user: user_1, conversation: accessible_conversation, account: account)
        create(:conversation_participant, user: user_1, conversation: revoked_conversation, account: account)
        revoked_membership.destroy!

        result = conversation_finder.perform

        expect(result[:conversations].map(&:id)).to contain_exactly(accessible_conversation.id)
      end

      it 'excludes the inaccessible conversation from the meta counts too' do
        accessible_conversation = create(:conversation, account: account, inbox: inbox)
        revoked_conversation = create(:conversation, account: account, inbox: restricted_inbox)
        revoked_membership = create(:inbox_member, user: user_1, inbox: restricted_inbox)
        create(:conversation_participant, user: user_1, conversation: accessible_conversation, account: account)
        create(:conversation_participant, user: user_1, conversation: revoked_conversation, account: account)
        revoked_membership.destroy!

        result = conversation_finder.perform_meta_only

        expect(result[:count][:all_count]).to eq 1
      end
    end
  end
end
