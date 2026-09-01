/* global axios */
import ApiClient from './ApiClient';

class CallAnalysesAPI extends ApiClient {
  constructor() {
    super('call_analyses', { accountScoped: true });
  }

  getNeedsReview() {
    return axios.get(this.url);
  }

  getRecent() {
    return axios.get(`${this.url}/recent`);
  }

  getDetail(id) {
    return axios.get(`${this.url}/${id}`);
  }

  retry(id) {
    return axios.post(`${this.url}/${id}/retry`);
  }
}

export default new CallAnalysesAPI();
