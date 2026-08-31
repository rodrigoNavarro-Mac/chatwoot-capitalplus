/* global axios */
import ApiClient from './ApiClient';

class CallAnalysesAPI extends ApiClient {
  constructor() {
    super('call_analyses', { accountScoped: true });
  }

  getNeedsReview() {
    return axios.get(this.url);
  }

  retry(id) {
    return axios.post(`${this.url}/${id}/retry`);
  }
}

export default new CallAnalysesAPI();
