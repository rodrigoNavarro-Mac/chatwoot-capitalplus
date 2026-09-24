/* global axios */

import ApiClient from './ApiClient';

class QuotesAPI extends ApiClient {
  constructor() {
    super('quotes', { accountScoped: true });
  }

  downloadPdf(id) {
    return axios.get(`${this.url}/${id}/pdf`, { responseType: 'blob' });
  }
}

export default new QuotesAPI();
