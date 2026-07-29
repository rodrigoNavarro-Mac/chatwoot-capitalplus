/* global axios */

import ApiClient from './ApiClient';

class AccountActions extends ApiClient {
  constructor() {
    super('actions', { accountScoped: true });
  }

  merge(parentId, childId) {
    return axios.post(`${this.url}/contact_merge`, {
      base_contact_id: parentId,
      mergee_contact_id: childId,
    });
  }

  mergeConversation(baseConversationId, mergeeConversationId) {
    return axios.post(`${this.url}/conversation_merge`, {
      base_conversation_id: baseConversationId,
      mergee_conversation_id: mergeeConversationId,
    });
  }
}

export default new AccountActions();
