/* global axios */
import ApiClient from './ApiClient';

class CallAnalysesAPI extends ApiClient {
  constructor() {
    super('call_analyses', { accountScoped: true });
  }

  getNeedsReview() {
    return axios.get(this.url);
  }

  getRecent({
    since,
    until,
    agentId,
    inboxId,
    confidence,
    conversationType,
    page,
  } = {}) {
    return axios.get(`${this.url}/recent`, {
      params: {
        since,
        until,
        agent_id: agentId,
        inbox_id: inboxId,
        confidence,
        conversation_type: conversationType,
        page,
      },
    });
  }

  getDetail(id) {
    return axios.get(`${this.url}/${id}`);
  }

  retry(id) {
    return axios.post(`${this.url}/${id}/retry`);
  }
}

export default new CallAnalysesAPI();
